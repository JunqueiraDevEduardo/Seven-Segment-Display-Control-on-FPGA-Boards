----------------------------------------------------------------------------
-- slot_machine_fsm.vhd
-- Máquina de Estados da Slot Machine com 6 Carretéis (3 + 3) e Créditos
--
-- Layout nos Displays:
--   [AN7 AN6 AN5] : 3 Carretéis (Grupo 1)
--   [AN4 AN3 AN2] : 3 Carretéis (Grupo 2)
--   [AN1 AN0]     : 2 Dígitos para Créditos do Jogador
----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity slot_machine_fsm is
    generic (
        SIM_SPEEDUP : boolean := false
    );
    port (
        clk            : in  STD_LOGIC;
        reset          : in  STD_LOGIC;
        btn_spin_pulse : in  STD_LOGIC;                  -- Disparo da jogada (SPIN)
        rand_val       : in  unsigned(7 downto 0);       -- Valor aleatório bruto
        rand_reel1     : in  unsigned(3 downto 0);      -- Dígito aleatório 1
        rand_reel2     : in  unsigned(3 downto 0);      -- Dígito aleatório 2
        rand_reel3     : in  unsigned(3 downto 0);      -- Dígito aleatório 3
        rand_reel4     : in  unsigned(3 downto 0);      -- Dígito aleatório 4
        rand_reel5     : in  unsigned(3 downto 0);      -- Dígito aleatório 5
        rand_reel6     : in  unsigned(3 downto 0);      -- Dígito aleatório 6
        disp_reel1     : out unsigned(3 downto 0);      -- Carretel 1 (AN7)
        disp_reel2     : out unsigned(3 downto 0);      -- Carretel 2 (AN6)
        disp_reel3     : out unsigned(3 downto 0);      -- Carretel 3 (AN5)
        disp_reel4     : out unsigned(3 downto 0);      -- Carretel 4 (AN4)
        disp_reel5     : out unsigned(3 downto 0);      -- Carretel 5 (AN3)
        disp_reel6     : out unsigned(3 downto 0);      -- Carretel 6 (AN2)
        credits_out    : out integer range 0 to 99;      -- Créditos (AN1 AN0)
        led_win        : out STD_LOGIC;                  -- LED 15 (Vitória)
        spin_active    : out STD_LOGIC;                  -- Rotação ativa
        payout_active  : out STD_LOGIC;                  -- Pagamento ativo
        led_effects    : out STD_LOGIC_VECTOR(6 downto 0); -- Luzes nos LEDs 14..8
        fsm_state_code : out STD_LOGIC_VECTOR(2 downto 0)
    );
end slot_machine_fsm;

architecture Behavioral of slot_machine_fsm is

    type state_t is (
        S_WAIT_SPIN,
        S_DEDUCT_BET,
        S_SPIN_REELS,
        S_CHECK_RESULT,
        S_PAYOUT
    );

    signal current_state : state_t := S_WAIT_SPIN;

    -- Temporizadores a 100 MHz para paragem sequencial dos 6 carretéis
    function get_stop_cycles(step : integer) return integer is
    begin
        if SIM_SPEEDUP then
            return step * 25;
        else
            case step is
                when 1 => return 50_000_000;   -- 0.5 s (Carretel 1)
                when 2 => return 80_000_000;   -- 0.8 s (Carretel 2)
                when 3 => return 110_000_000;  -- 1.1 s (Carretel 3 - Fecha 1º trio!)
                when 4 => return 150_000_000;  -- 1.5 s (Carretel 4)
                when 5 => return 180_000_000;  -- 1.8 s (Carretel 5)
                when others => return 220_000_000; -- 2.2 s (Carretel 6 - Fecha 2º trio!)
            end case;
        end if;
    end function;

    function get_frame_cycles return integer is
    begin
        if SIM_SPEEDUP then return 8; else return 3_000_000; end if;     -- 30 ms
    end function;

    function get_payout_cycles return integer is
    begin
        if SIM_SPEEDUP then return 100; else return 150_000_000; end if; -- 1.5 s
    end function;

    constant STOP1 : integer := get_stop_cycles(1);
    constant STOP2 : integer := get_stop_cycles(2);
    constant STOP3 : integer := get_stop_cycles(3);
    constant STOP4 : integer := get_stop_cycles(4);
    constant STOP5 : integer := get_stop_cycles(5);
    constant STOP6 : integer := get_stop_cycles(6);
    constant FRAME_CYCLES  : integer := get_frame_cycles;
    constant PAYOUT_CYCLES : integer := get_payout_cycles;

    -- Contadores
    signal timer_cnt : unsigned(27 downto 0) := (others => '0');
    signal frame_cnt : unsigned(21 downto 0) := (others => '0');
    signal anim_cnt  : unsigned(24 downto 0) := (others => '0');
    signal chaser_idx: integer range 0 to 6 := 0;

    -- Registos dos 6 carretéis
    signal credits_reg : integer range 0 to 99 := 50;
    signal reel1_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);
    signal reel2_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);
    signal reel3_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);
    signal reel4_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);
    signal reel5_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);
    signal reel6_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);

    -- Alvos finais calculados na aposta
    signal target_reel1: unsigned(3 downto 0) := to_unsigned(7, 4);
    signal target_reel2: unsigned(3 downto 0) := to_unsigned(7, 4);
    signal target_reel3: unsigned(3 downto 0) := to_unsigned(7, 4);
    signal target_reel4: unsigned(3 downto 0) := to_unsigned(7, 4);
    signal target_reel5: unsigned(3 downto 0) := to_unsigned(7, 4);
    signal target_reel6: unsigned(3 downto 0) := to_unsigned(7, 4);

    signal win_reg     : STD_LOGIC := '0';
    signal win_prize   : integer range 0 to 50 := 0;
    signal led_fx_reg  : STD_LOGIC_VECTOR(6 downto 0) := (others => '0');

begin

    process(clk)
        variable r_num : integer range 0 to 255;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                current_state <= S_WAIT_SPIN;
                credits_reg   <= 50;
                reel1_reg     <= to_unsigned(7, 4);
                reel2_reg     <= to_unsigned(7, 4);
                reel3_reg     <= to_unsigned(7, 4);
                reel4_reg     <= to_unsigned(7, 4);
                reel5_reg     <= to_unsigned(7, 4);
                reel6_reg     <= to_unsigned(7, 4);
                target_reel1  <= to_unsigned(7, 4);
                target_reel2  <= to_unsigned(7, 4);
                target_reel3  <= to_unsigned(7, 4);
                target_reel4  <= to_unsigned(7, 4);
                target_reel5  <= to_unsigned(7, 4);
                target_reel6  <= to_unsigned(7, 4);
                win_reg       <= '0';
                win_prize     <= 0;
                timer_cnt     <= (others => '0');
                frame_cnt     <= (others => '0');
                anim_cnt      <= (others => '0');
                chaser_idx    <= 0;
                led_fx_reg    <= (others => '0');
            else

                -- Contador visual dos LEDs
                if anim_cnt >= 9_999_999 or SIM_SPEEDUP then
                    anim_cnt <= (others => '0');
                    if chaser_idx = 6 then
                        chaser_idx <= 0;
                    else
                        chaser_idx <= chaser_idx + 1;
                    end if;
                else
                    anim_cnt <= anim_cnt + 1;
                end if;

                case current_state is

                    ------------------------------------------------------------
                    -- 1. WAIT FOR SPIN
                    ------------------------------------------------------------
                    when S_WAIT_SPIN =>
                        timer_cnt  <= (others => '0');
                        frame_cnt  <= (others => '0');
                        led_fx_reg <= (others => '0');
                        if btn_spin_pulse = '1' then
                            if credits_reg > 0 then
                                current_state <= S_DEDUCT_BET;
                            else
                                credits_reg   <= 20; -- Recarga automática se zerar
                                current_state <= S_DEDUCT_BET;
                            end if;
                        end if;

                    ------------------------------------------------------------
                    -- 2. DEDUCT BET: Subtrai 1 crédito e sorteia os 6 carretéis
                    ------------------------------------------------------------
                    when S_DEDUCT_BET =>
                        if credits_reg > 0 then
                            credits_reg <= credits_reg - 1;
                        end if;
                        win_reg   <= '0';
                        timer_cnt <= (others => '0');
                        frame_cnt <= (others => '0');

                        r_num := to_integer(rand_val);

                        -- Sorteio de resultados:
                        -- MEGA JACKPOT duplo (777 777) ~5% de chance
                        if r_num >= 240 then
                            target_reel1 <= to_unsigned(7, 4);
                            target_reel2 <= to_unsigned(7, 4);
                            target_reel3 <= to_unsigned(7, 4);
                            target_reel4 <= to_unsigned(7, 4);
                            target_reel5 <= to_unsigned(7, 4);
                            target_reel6 <= to_unsigned(7, 4);
                            win_prize    <= 30; -- +30 créditos!

                        -- JACKPOT no 1º trio (777) ~15% de chance
                        elsif r_num >= 200 then
                            target_reel1 <= to_unsigned(7, 4);
                            target_reel2 <= to_unsigned(7, 4);
                            target_reel3 <= to_unsigned(7, 4);
                            target_reel4 <= to_unsigned((r_num mod 7) + 1, 4);
                            target_reel5 <= to_unsigned(((r_num / 3) mod 7) + 2, 4);
                            target_reel6 <= to_unsigned(((r_num / 5) mod 7) + 3, 4);
                            win_prize    <= 15;

                        -- JACKPOT no 2º trio (555 ou 777) ~15% de chance
                        elsif r_num >= 160 then
                            target_reel1 <= to_unsigned((r_num mod 7) + 1, 4);
                            target_reel2 <= to_unsigned(((r_num / 3) mod 7) + 2, 4);
                            target_reel3 <= to_unsigned(((r_num / 5) mod 7) + 3, 4);
                            target_reel4 <= to_unsigned(5, 4);
                            target_reel5 <= to_unsigned(5, 4);
                            target_reel6 <= to_unsigned(5, 4);
                            win_prize    <= 12;

                        -- Vitória comum (333 num dos trios) ~15% de chance
                        elsif r_num >= 120 then
                            target_reel1 <= to_unsigned(3, 4);
                            target_reel2 <= to_unsigned(3, 4);
                            target_reel3 <= to_unsigned(3, 4);
                            target_reel4 <= to_unsigned((r_num mod 8) + 1, 4);
                            target_reel5 <= to_unsigned(((r_num / 2) mod 8) + 2, 4);
                            target_reel6 <= to_unsigned(((r_num / 4) mod 8) + 1, 4);
                            win_prize    <= 8;

                        -- DERROTA: Símbolos todos desalinhados
                        else
                            target_reel1 <= to_unsigned((r_num mod 7) + 1, 4);
                            target_reel2 <= to_unsigned(((r_num / 3) mod 7) + 2, 4);
                            target_reel3 <= to_unsigned(((r_num / 7) mod 7) + 3, 4);
                            target_reel4 <= to_unsigned(((r_num + 2) mod 9) + 1, 4);
                            target_reel5 <= to_unsigned(((r_num / 2) mod 7) + 2, 4);
                            target_reel6 <= to_unsigned(((r_num + 5) mod 8) + 1, 4);
                            win_prize    <= 0;
                        end if;

                        current_state <= S_SPIN_REELS;

                    ------------------------------------------------------------
                    -- 3. SPIN REELS: Paragem sequencial dos 6 carretéis
                    ------------------------------------------------------------
                    when S_SPIN_REELS =>
                        timer_cnt <= timer_cnt + 1;

                        -- Luzes em movimento nos LEDs
                        case chaser_idx is
                            when 0 => led_fx_reg <= "0000001";
                            when 1 => led_fx_reg <= "0000010";
                            when 2 => led_fx_reg <= "0000100";
                            when 3 => led_fx_reg <= "0001000";
                            when 4 => led_fx_reg <= "0010000";
                            when 5 => led_fx_reg <= "0100000";
                            when others => led_fx_reg <= "1000000";
                        end case;

                        if frame_cnt >= to_unsigned(FRAME_CYCLES - 1, frame_cnt'length) then
                            frame_cnt <= (others => '0');

                            -- 1º Trio (AN7, AN6, AN5)
                            if timer_cnt < to_unsigned(STOP1, timer_cnt'length) then
                                reel1_reg <= rand_reel1;
                            else
                                reel1_reg <= target_reel1;
                            end if;

                            if timer_cnt < to_unsigned(STOP2, timer_cnt'length) then
                                reel2_reg <= rand_reel2;
                            else
                                reel2_reg <= target_reel2;
                            end if;

                            if timer_cnt < to_unsigned(STOP3, timer_cnt'length) then
                                reel3_reg <= rand_reel3;
                            else
                                reel3_reg <= target_reel3;
                            end if;

                            -- 2º Trio (AN4, AN3, AN2)
                            if timer_cnt < to_unsigned(STOP4, timer_cnt'length) then
                                reel4_reg <= rand_reel4;
                            else
                                reel4_reg <= target_reel4;
                            end if;

                            if timer_cnt < to_unsigned(STOP5, timer_cnt'length) then
                                reel5_reg <= rand_reel5;
                            else
                                reel5_reg <= target_reel5;
                            end if;

                            if timer_cnt < to_unsigned(STOP6, timer_cnt'length) then
                                reel6_reg <= rand_reel6;
                            else
                                reel6_reg <= target_reel6;
                            end if;
                        else
                            frame_cnt <= frame_cnt + 1;
                        end if;

                        if timer_cnt >= to_unsigned(STOP6, timer_cnt'length) then
                            reel1_reg <= target_reel1;
                            reel2_reg <= target_reel2;
                            reel3_reg <= target_reel3;
                            reel4_reg <= target_reel4;
                            reel5_reg <= target_reel5;
                            reel6_reg <= target_reel6;
                            current_state <= S_CHECK_RESULT;
                        end if;

                    ------------------------------------------------------------
                    -- 4. CHECK RESULT
                    ------------------------------------------------------------
                    when S_CHECK_RESULT =>
                        timer_cnt <= (others => '0');
                        if win_prize > 0 then
                            win_reg <= '1';
                        else
                            win_reg <= '0';
                        end if;
                        current_state <= S_PAYOUT;

                    ------------------------------------------------------------
                    -- 5. PAYOUT: Celebração de prémio nos LEDs e Créditos
                    ------------------------------------------------------------
                    when S_PAYOUT =>
                        timer_cnt <= timer_cnt + 1;

                        if win_reg = '1' then
                            if anim_cnt(23) = '1' or SIM_SPEEDUP then
                                led_fx_reg <= "1111111";
                            else
                                led_fx_reg <= "0000000";
                            end if;
                        else
                            led_fx_reg <= "0000000";
                        end if;

                        if timer_cnt = 1 and win_reg = '1' then
                            if credits_reg + win_prize <= 99 then
                                credits_reg <= credits_reg + win_prize;
                            else
                                credits_reg <= 99;
                            end if;
                        end if;

                        if timer_cnt >= to_unsigned(PAYOUT_CYCLES - 1, timer_cnt'length) then
                            current_state <= S_WAIT_SPIN;
                        end if;

                end case;
            end if;
        end if;
    end process;

    disp_reel1  <= reel1_reg;
    disp_reel2  <= reel2_reg;
    disp_reel3  <= reel3_reg;
    disp_reel4  <= reel4_reg;
    disp_reel5  <= reel5_reg;
    disp_reel6  <= reel6_reg;
    credits_out <= credits_reg;

    led_win     <= win_reg;
    led_effects <= led_fx_reg;

    spin_active   <= '1' when current_state = S_SPIN_REELS else '0';
    payout_active <= '1' when current_state = S_PAYOUT else '0';

    with current_state select
        fsm_state_code <= "000" when S_WAIT_SPIN,
                          "001" when S_DEDUCT_BET,
                          "010" when S_SPIN_REELS,
                          "011" when S_CHECK_RESULT,
                          "100" when S_PAYOUT,
                          "111" when others;

end Behavioral;
