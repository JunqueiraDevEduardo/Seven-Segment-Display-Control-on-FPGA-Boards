----------------------------------------------------------------------------
-- slot_machine_fsm.vhd
-- Máquina de Estados da Slot Machine Adaptativa (Layout estilo Altera DE2 / Nexys-4 DDR)
-- Adaptação fiel ao projeto CPE 100L do vídeo e ao artigo IEEE 2025:
--   - 4 Carretéis na zona direita com paragem sequencial:
--       * Carretel 1 trava aos 0.6s
--       * Carretel 2 trava aos 1.1s
--       * Carretel 3 trava aos 1.6s
--       * Carretel 4 trava aos 2.1s (suspense final para Jackpot 7-7-7-7!)
--   - Efeito visual de rotação e festa nos LEDs
--   - Integração com o limiar adaptativo dinâmico
----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity slot_machine_fsm is
    generic (
        SIM_SPEEDUP : boolean := false
    );
    port (
        clk                   : in  STD_LOGIC;
        reset                 : in  STD_LOGIC;
        btn_spin_pulse        : in  STD_LOGIC;                  -- Disparo da jogada (SPIN)
        current_threshold     : in  integer range 0 to 99;      -- Limiar dinâmico do artigo
        rand_100              : in  integer range 0 to 99;      -- Número aleatório do LFSR
        rand_reel1            : in  unsigned(3 downto 0);      -- Dígito carretel 1
        rand_reel2            : in  unsigned(3 downto 0);      -- Dígito carretel 2
        rand_reel3            : in  unsigned(3 downto 0);      -- Dígito carretel 3
        rand_reel4            : in  unsigned(3 downto 0);      -- Dígito carretel 4
        disp_reel1            : out unsigned(3 downto 0);      -- Display carretel 1 (AN0)
        disp_reel2            : out unsigned(3 downto 0);      -- Display carretel 2 (AN1)
        disp_reel3            : out unsigned(3 downto 0);      -- Display carretel 3 (AN2)
        disp_reel4            : out unsigned(3 downto 0);      -- Display carretel 4 (AN3)
        credits_out           : out integer range 0 to 99;      -- Créditos do jogador (AN7 AN6)
        led_win               : out STD_LOGIC;                  -- Indicador de vitória (LED 15)
        spin_active           : out STD_LOGIC;                  -- Em rotação
        payout_active         : out STD_LOGIC;                  -- Em pagamento
        update_threshold_tick : out STD_LOGIC;                  -- Pulso para recálculo do limiar
        last_was_win          : out STD_LOGIC;                  -- Flag de vitória
        led_effects           : out STD_LOGIC_VECTOR(6 downto 0); -- Efeitos nos LEDs 14..8
        fsm_state_code        : out STD_LOGIC_VECTOR(2 downto 0)  -- Código de depuração
    );
end slot_machine_fsm;

architecture Behavioral of slot_machine_fsm is

    type state_t is (
        S_WAIT_SPIN,
        S_DEDUCT_BET,
        S_SPIN_REELS,
        S_CHECK_RESULT,
        S_PAYOUT,
        S_ADJUST_THRESHOLD
    );

    signal current_state : state_t := S_WAIT_SPIN;

    -- Temporização dos 4 carretéis sequenciais (100 MHz ou acelerado em simulação)
    function get_stop1_cycles return integer is
    begin
        if SIM_SPEEDUP then return 40; else return 60_000_000; end if;   -- 0.6 s
    end function;

    function get_stop2_cycles return integer is
    begin
        if SIM_SPEEDUP then return 80; else return 110_000_000; end if;  -- 1.1 s
    end function;

    function get_stop3_cycles return integer is
    begin
        if SIM_SPEEDUP then return 120; else return 160_000_000; end if; -- 1.6 s
    end function;

    function get_total_spin_cycles return integer is
    begin
        if SIM_SPEEDUP then return 160; else return 210_000_000; end if; -- 2.1 s
    end function;

    function get_frame_cycles return integer is
    begin
        if SIM_SPEEDUP then return 8; else return 3_000_000; end if;     -- 30 ms
    end function;

    function get_payout_cycles return integer is
    begin
        if SIM_SPEEDUP then return 100; else return 150_000_000; end if; -- 1.5 s
    end function;

    constant SPIN_STOP1_CYCLES : integer := get_stop1_cycles;
    constant SPIN_STOP2_CYCLES : integer := get_stop2_cycles;
    constant SPIN_STOP3_CYCLES : integer := get_stop3_cycles;
    constant SPIN_TOTAL_CYCLES : integer := get_total_spin_cycles;
    constant FRAME_CYCLES      : integer := get_frame_cycles;
    constant PAYOUT_CYCLES     : integer := get_payout_cycles;

    -- Contadores
    signal timer_cnt : unsigned(27 downto 0) := (others => '0');
    signal frame_cnt : unsigned(21 downto 0) := (others => '0');
    signal anim_cnt  : unsigned(24 downto 0) := (others => '0');
    signal chaser_idx: integer range 0 to 6 := 0;

    -- Registos dos 4 carretéis
    signal credits_reg : integer range 0 to 99 := 50;
    signal reel1_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);
    signal reel2_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);
    signal reel3_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);
    signal reel4_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);

    -- Alvos finais calculados na aposta
    signal target_reel1: unsigned(3 downto 0) := to_unsigned(7, 4);
    signal target_reel2: unsigned(3 downto 0) := to_unsigned(7, 4);
    signal target_reel3: unsigned(3 downto 0) := to_unsigned(7, 4);
    signal target_reel4: unsigned(3 downto 0) := to_unsigned(7, 4);
    signal is_win_spin : STD_LOGIC := '0';
    signal win_type    : integer range 0 to 3 := 0;

    signal win_reg     : STD_LOGIC := '0';
    signal led_fx_reg  : STD_LOGIC_VECTOR(6 downto 0) := (others => '0');

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                current_state <= S_WAIT_SPIN;
                credits_reg   <= 50;
                reel1_reg     <= to_unsigned(7, 4);
                reel2_reg     <= to_unsigned(7, 4);
                reel3_reg     <= to_unsigned(7, 4);
                reel4_reg     <= to_unsigned(7, 4);
                target_reel1  <= to_unsigned(7, 4);
                target_reel2  <= to_unsigned(7, 4);
                target_reel3  <= to_unsigned(7, 4);
                target_reel4  <= to_unsigned(7, 4);
                win_reg       <= '0';
                is_win_spin   <= '0';
                win_type      <= 0;
                timer_cnt     <= (others => '0');
                frame_cnt     <= (others => '0');
                anim_cnt      <= (others => '0');
                chaser_idx    <= 0;
                led_fx_reg    <= (others => '0');
            else

                -- Contador para efeitos visuais rápidos nos LEDs
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
                    -- 2. DEDUCT BET: Subtrai crédito e gera alvos pseudo-aleatórios
                    ------------------------------------------------------------
                    when S_DEDUCT_BET =>
                        if credits_reg > 0 then
                            credits_reg <= credits_reg - 1;
                        end if;
                        win_reg   <= '0';
                        timer_cnt <= (others => '0');
                        frame_cnt <= (others => '0');

                        -- Compara com o limiar dinâmico adaptativo
                        if rand_100 >= current_threshold then
                            is_win_spin <= '1';
                            if rand_100 >= 90 then
                                target_reel1 <= to_unsigned(7, 4);
                                target_reel2 <= to_unsigned(7, 4);
                                target_reel3 <= to_unsigned(7, 4);
                                target_reel4 <= to_unsigned(7, 4); -- 7-7-7-7 JACKPOT!
                                win_type     <= 3;
                            elsif rand_100 >= 75 then
                                target_reel1 <= to_unsigned(5, 4);
                                target_reel2 <= to_unsigned(5, 4);
                                target_reel3 <= to_unsigned(5, 4);
                                target_reel4 <= to_unsigned(5, 4); -- 5-5-5-5
                                win_type     <= 2;
                            elsif rand_100 >= 60 then
                                target_reel1 <= to_unsigned(3, 4);
                                target_reel2 <= to_unsigned(3, 4);
                                target_reel3 <= to_unsigned(3, 4);
                                target_reel4 <= to_unsigned(3, 4); -- 3-3-3-3
                                win_type     <= 1;
                            else
                                target_reel1 <= to_unsigned(1, 4);
                                target_reel2 <= to_unsigned(1, 4);
                                target_reel3 <= to_unsigned(1, 4);
                                target_reel4 <= to_unsigned(1, 4); -- 1-1-1-1
                                win_type     <= 0;
                            end if;
                        else
                            is_win_spin <= '0';
                            win_type    <= 0;
                            target_reel1 <= to_unsigned((rand_100 mod 7) + 1, 4);
                            target_reel2 <= to_unsigned(((rand_100 / 3) mod 7) + 2, 4);
                            target_reel3 <= to_unsigned(((rand_100 / 7) mod 7) + 3, 4);
                            target_reel4 <= to_unsigned(((rand_100 + 5) mod 9) + 1, 4);
                        end if;

                        current_state <= S_SPIN_REELS;

                    ------------------------------------------------------------
                    -- 3. SPIN REELS: Paragem sequencial dos 4 carretéis
                    ------------------------------------------------------------
                    when S_SPIN_REELS =>
                        timer_cnt <= timer_cnt + 1;

                        -- Efeito chaser nos LEDs
                        case chaser_idx is
                            when 0 => led_fx_reg <= "0000001";
                            when 1 => led_fx_reg <= "0000010";
                            when 2 => led_fx_reg <= "0000100";
                            when 3 => led_fx_reg <= "0001000";
                            when 4 => led_fx_reg <= "0010000";
                            when 5 => led_fx_reg <= "0100000";
                            when others => led_fx_reg <= "1000000";
                        end case;

                        -- Atualização rápida dos números enquanto giram
                        if frame_cnt >= to_unsigned(FRAME_CYCLES - 1, frame_cnt'length) then
                            frame_cnt <= (others => '0');

                            -- Carretel 1 trava aos 0.6s
                            if timer_cnt < to_unsigned(SPIN_STOP1_CYCLES, timer_cnt'length) then
                                reel1_reg <= rand_reel1;
                            else
                                reel1_reg <= target_reel1;
                            end if;

                            -- Carretel 2 trava aos 1.1s
                            if timer_cnt < to_unsigned(SPIN_STOP2_CYCLES, timer_cnt'length) then
                                reel2_reg <= rand_reel2;
                            else
                                reel2_reg <= target_reel2;
                            end if;

                            -- Carretel 3 trava aos 1.6s
                            if timer_cnt < to_unsigned(SPIN_STOP3_CYCLES, timer_cnt'length) then
                                reel3_reg <= rand_reel3;
                            else
                                reel3_reg <= target_reel3;
                            end if;

                            -- Carretel 4 trava aos 2.1s
                            if timer_cnt < to_unsigned(SPIN_TOTAL_CYCLES, timer_cnt'length) then
                                reel4_reg <= rand_reel4;
                            else
                                reel4_reg <= target_reel4;
                            end if;
                        else
                            frame_cnt <= frame_cnt + 1;
                        end if;

                        if timer_cnt >= to_unsigned(SPIN_TOTAL_CYCLES, timer_cnt'length) then
                            reel1_reg <= target_reel1;
                            reel2_reg <= target_reel2;
                            reel3_reg <= target_reel3;
                            reel4_reg <= target_reel4;
                            current_state <= S_CHECK_RESULT;
                        end if;

                    ------------------------------------------------------------
                    -- 4. CHECK RESULT
                    ------------------------------------------------------------
                    when S_CHECK_RESULT =>
                        timer_cnt <= (others => '0');
                        win_reg   <= is_win_spin;
                        current_state <= S_PAYOUT;

                    ------------------------------------------------------------
                    -- 5. PAYOUT: Celebração e atribuição de créditos
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

                        if timer_cnt = 1 then
                            if win_reg = '1' then
                                case win_type is
                                    when 3 => -- 7-7-7-7 (+20 créditos)
                                        if credits_reg + 20 <= 99 then
                                            credits_reg <= credits_reg + 20;
                                        else
                                            credits_reg <= 99;
                                        end if;
                                    when 2 => -- 5-5-5-5 (+15 créditos)
                                        if credits_reg + 15 <= 99 then
                                            credits_reg <= credits_reg + 15;
                                        else
                                            credits_reg <= 99;
                                        end if;
                                    when others => -- Outras vitórias (+10 créditos)
                                        if credits_reg + 10 <= 99 then
                                            credits_reg <= credits_reg + 10;
                                        else
                                            credits_reg <= 99;
                                        end if;
                                end case;
                            end if;
                        end if;

                        if timer_cnt >= to_unsigned(PAYOUT_CYCLES - 1, timer_cnt'length) then
                            current_state <= S_ADJUST_THRESHOLD;
                        end if;

                    ------------------------------------------------------------
                    -- 6. ADJUST THRESHOLD
                    ------------------------------------------------------------
                    when S_ADJUST_THRESHOLD =>
                        current_state <= S_WAIT_SPIN;

                end case;
            end if;
        end if;
    end process;

    disp_reel1 <= reel1_reg;
    disp_reel2 <= reel2_reg;
    disp_reel3 <= reel3_reg;
    disp_reel4 <= reel4_reg;
    credits_out <= credits_reg;

    led_win      <= win_reg;
    last_was_win <= win_reg;
    led_effects  <= led_fx_reg;

    spin_active   <= '1' when current_state = S_SPIN_REELS else '0';
    payout_active <= '1' when current_state = S_PAYOUT else '0';

    update_threshold_tick <= '1' when current_state = S_ADJUST_THRESHOLD else '0';

    with current_state select
        fsm_state_code <= "000" when S_WAIT_SPIN,
                          "001" when S_DEDUCT_BET,
                          "010" when S_SPIN_REELS,
                          "011" when S_CHECK_RESULT,
                          "100" when S_PAYOUT,
                          "101" when S_ADJUST_THRESHOLD,
                          "111" when others;

end Behavioral;
