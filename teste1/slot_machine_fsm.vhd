----------------------------------------------------------------------------
-- slot_machine_fsm.vhd
-- Máquina de Estados da Slot Machine com 6 Carretéis (3 + 3)
--
-- Regras de Créditos:
--   - Perder nos dois trios: TIRA 5 CRÉDITOS (-5)
--   - Ganhar num trio de três: GANHA 10 CRÉDITOS (+10)
--   - Ganhar nos dois trios de três: GANHA 15 CRÉDITOS (+15)
--
-- Efeitos de Celebração de Vitória:
--   - Duração: 5 SEGUNDOS
--   - Todos os 16 LEDs da placa a piscar em uníssono (Blinker ~4 Hz)
--   - LEDs RGB LD16 e LD17 a alternar entre cores vivas (Vermelho, Verde, Azul, Amarelo, Ciano, Magenta, Branco)
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
        led_win        : out STD_LOGIC;                  -- Indicador de vitória
        spin_active    : out STD_LOGIC;                  -- Rotação ativa
        payout_active  : out STD_LOGIC;                  -- Celebração ativa (5s)
        blink_all_leds : out STD_LOGIC;                  -- Pulso de piscar para todos os 16 LEDs
        chaser_leds    : out STD_LOGIC_VECTOR(6 downto 0); -- Corrida de luzes na rotação
        rgb16_r        : out STD_LOGIC;                  -- LD16 Vermelho
        rgb16_g        : out STD_LOGIC;                  -- LD16 Verde
        rgb16_b        : out STD_LOGIC;                  -- LD16 Azul
        rgb17_r        : out STD_LOGIC;                  -- LD17 Vermelho
        rgb17_g        : out STD_LOGIC;                  -- LD17 Verde
        rgb17_b        : out STD_LOGIC;                  -- LD17 Azul
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

    -- Temporizadores sequenciais de paragem dos carretéis
    function get_stop_cycles(step : integer) return integer is
    begin
        if SIM_SPEEDUP then
            return step * 25;
        else
            case step is
                when 1 => return 50_000_000;   -- 0.5 s (Carretel 1)
                when 2 => return 80_000_000;   -- 0.8 s (Carretel 2)
                when 3 => return 110_000_000;  -- 1.1 s (Carretel 3 - Fecha 1º trio)
                when 4 => return 150_000_000;  -- 1.5 s (Carretel 4)
                when 5 => return 180_000_000;  -- 1.8 s (Carretel 5)
                when others => return 220_000_000; -- 2.2 s (Carretel 6 - Fecha 2º trio)
            end case;
        end if;
    end function;

    function get_frame_cycles return integer is
    begin
        if SIM_SPEEDUP then return 8; else return 3_000_000; end if;     -- 30 ms
    end function;

    -- 5 SEGUNDOS DE FESTA EM VITÓRIA (500 milhões de ciclos a 100 MHz)
    function get_win_payout_cycles return integer is
    begin
        if SIM_SPEEDUP then return 250; else return 500_000_000; end if; -- 5.0 s
    end function;

    -- 1 SEGUNDO DE PAUSA EM DERROTA
    function get_loss_payout_cycles return integer is
    begin
        if SIM_SPEEDUP then return 50; else return 100_000_000; end if;  -- 1.0 s
    end function;

    constant STOP1 : integer := get_stop_cycles(1);
    constant STOP2 : integer := get_stop_cycles(2);
    constant STOP3 : integer := get_stop_cycles(3);
    constant STOP4 : integer := get_stop_cycles(4);
    constant STOP5 : integer := get_stop_cycles(5);
    constant STOP6 : integer := get_stop_cycles(6);
    constant FRAME_CYCLES       : integer := get_frame_cycles;
    constant WIN_PAYOUT_CYCLES  : integer := get_win_payout_cycles;
    constant LOSS_PAYOUT_CYCLES : integer := get_loss_payout_cycles;

    -- Contadores (29 bits suporta mais de 500_000_000 ciclos)
    signal timer_cnt : unsigned(29 downto 0) := (others => '0');
    signal frame_cnt : unsigned(21 downto 0) := (others => '0');
    signal anim_cnt  : unsigned(24 downto 0) := (others => '0');
    signal chaser_idx: integer range 0 to 6 := 0;

    -- Contador de cores RGB (~250 ms por cor)
    signal rgb_step  : integer range 0 to 6 := 0;
    signal blink_state : STD_LOGIC := '0';

    -- Registos dos 6 carretéis
    signal credits_reg : integer range 0 to 99 := 50;
    signal reel1_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);
    signal reel2_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);
    signal reel3_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);
    signal reel4_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);
    signal reel5_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);
    signal reel6_reg   : unsigned(3 downto 0) := to_unsigned(7, 4);

    -- Alvos finais
    signal target_reel1: unsigned(3 downto 0) := to_unsigned(7, 4);
    signal target_reel2: unsigned(3 downto 0) := to_unsigned(7, 4);
    signal target_reel3: unsigned(3 downto 0) := to_unsigned(7, 4);
    signal target_reel4: unsigned(3 downto 0) := to_unsigned(7, 4);
    signal target_reel5: unsigned(3 downto 0) := to_unsigned(7, 4);
    signal target_reel6: unsigned(3 downto 0) := to_unsigned(7, 4);

    signal win_reg        : STD_LOGIC := '0';
    signal win_two_trios  : STD_LOGIC := '0';
    signal win_one_trio   : STD_LOGIC := '0';
    signal chaser_reg     : STD_LOGIC_VECTOR(6 downto 0) := (others => '0');

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
                win_two_trios <= '0';
                win_one_trio  <= '0';
                timer_cnt     <= (others => '0');
                frame_cnt     <= (others => '0');
                anim_cnt      <= (others => '0');
                chaser_idx    <= 0;
                rgb_step      <= 0;
                blink_state   <= '0';
                chaser_reg    <= (others => '0');
            else

                -- Contador para piscar os 16 LEDs (~4 Hz) e alternar cores RGB (~4 Hz)
                if anim_cnt >= 12_499_999 or SIM_SPEEDUP then
                    anim_cnt <= (others => '0');
                    blink_state <= not blink_state;
                    if rgb_step = 6 then
                        rgb_step <= 0;
                    else
                        rgb_step <= rgb_step + 1;
                    end if;
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
                        chaser_reg <= (others => '0');
                        if btn_spin_pulse = '1' then
                            if credits_reg < 5 then
                                -- Se tiver menos de 5 créditos, recarrega para 50
                                credits_reg <= 50;
                            end if;
                            current_state <= S_DEDUCT_BET;
                        end if;

                    ------------------------------------------------------------
                    -- 2. DEDUCT BET & SORTEIO DOS CARRETÉIS
                    ------------------------------------------------------------
                    when S_DEDUCT_BET =>
                        win_reg       <= '0';
                        win_two_trios <= '0';
                        win_one_trio  <= '0';
                        timer_cnt     <= (others => '0');
                        frame_cnt     <= (others => '0');

                        r_num := to_integer(rand_val);

                        -- Cenário A: GANHA NOS DOIS TRIOS (+15 créditos) ~15% de probabilidade
                        if r_num >= 215 then
                            target_reel1 <= to_unsigned(7, 4);
                            target_reel2 <= to_unsigned(7, 4);
                            target_reel3 <= to_unsigned(7, 4); -- Trio 1: 777
                            target_reel4 <= to_unsigned(7, 4);
                            target_reel5 <= to_unsigned(7, 4);
                            target_reel6 <= to_unsigned(7, 4); -- Trio 2: 777
                            win_two_trios <= '1';

                        -- Cenário B: GANHA NO 1º TRIO (+10 créditos) ~25% de probabilidade
                        elsif r_num >= 150 then
                            target_reel1 <= to_unsigned(7, 4);
                            target_reel2 <= to_unsigned(7, 4);
                            target_reel3 <= to_unsigned(7, 4); -- Trio 1: 777 (Ganhou!)
                            target_reel4 <= to_unsigned((r_num mod 7) + 1, 4);
                            target_reel5 <= to_unsigned(((r_num / 3) mod 7) + 2, 4);
                            target_reel6 <= to_unsigned(((r_num / 5) mod 7) + 3, 4); -- Trio 2: Desalinhado
                            win_one_trio <= '1';

                        -- Cenário C: GANHA NO 2º TRIO (+10 créditos) ~25% de probabilidade
                        elsif r_num >= 85 then
                            target_reel1 <= to_unsigned((r_num mod 7) + 1, 4);
                            target_reel2 <= to_unsigned(((r_num / 3) mod 7) + 2, 4);
                            target_reel3 <= to_unsigned(((r_num / 5) mod 7) + 3, 4); -- Trio 1: Desalinhado
                            target_reel4 <= to_unsigned(5, 4);
                            target_reel5 <= to_unsigned(5, 4);
                            target_reel6 <= to_unsigned(5, 4); -- Trio 2: 555 (Ganhou!)
                            win_one_trio <= '1';

                        -- Cenário D: PERDE NOS DOIS TRIOS (-5 créditos) ~35% de probabilidade
                        else
                            target_reel1 <= to_unsigned((r_num mod 7) + 1, 4);
                            target_reel2 <= to_unsigned(((r_num / 3) mod 7) + 2, 4);
                            target_reel3 <= to_unsigned(((r_num / 7) mod 7) + 3, 4);
                            target_reel4 <= to_unsigned(((r_num + 2) mod 9) + 1, 4);
                            target_reel5 <= to_unsigned(((r_num / 2) mod 7) + 2, 4);
                            target_reel6 <= to_unsigned(((r_num + 5) mod 8) + 1, 4);
                        end if;

                        current_state <= S_SPIN_REELS;

                    ------------------------------------------------------------
                    -- 3. SPIN REELS: Rotação sequencial dos 6 carretéis
                    ------------------------------------------------------------
                    when S_SPIN_REELS =>
                        timer_cnt <= timer_cnt + 1;

                        -- Chaser visual
                        case chaser_idx is
                            when 0 => chaser_reg <= "0000001";
                            when 1 => chaser_reg <= "0000010";
                            when 2 => chaser_reg <= "0000100";
                            when 3 => chaser_reg <= "0001000";
                            when 4 => chaser_reg <= "0010000";
                            when 5 => chaser_reg <= "0100000";
                            when others => chaser_reg <= "1000000";
                        end case;

                        if frame_cnt >= to_unsigned(FRAME_CYCLES - 1, frame_cnt'length) then
                            frame_cnt <= (others => '0');

                            -- 1º Trio
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

                            -- 2º Trio
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
                    -- 4. CHECK RESULT: Aplica regras de créditos
                    ------------------------------------------------------------
                    when S_CHECK_RESULT =>
                        timer_cnt <= (others => '0');

                        -- SE GANHOU NOS DOIS TRIOS (+15 créditos)
                        if win_two_trios = '1' then
                            win_reg <= '1';
                            if credits_reg + 15 <= 99 then
                                credits_reg <= credits_reg + 15;
                            else
                                credits_reg <= 99;
                            end if;

                        -- SE GANHOU NUM TRIO (+10 créditos)
                        elsif win_one_trio = '1' then
                            win_reg <= '1';
                            if credits_reg + 10 <= 99 then
                                credits_reg <= credits_reg + 10;
                            else
                                credits_reg <= 99;
                            end if;

                        -- SE PERDEU NOS DOIS TRIOS (-5 créditos)
                        else
                            win_reg <= '0';
                            if credits_reg >= 5 then
                                credits_reg <= credits_reg - 5;
                            else
                                credits_reg <= 0;
                            end if;
                        end if;

                        current_state <= S_PAYOUT;

                    ------------------------------------------------------------
                    -- 5. PAYOUT: Celebração de 5 SEGUNDOS em vitória
                    ------------------------------------------------------------
                    when S_PAYOUT =>
                        timer_cnt <= timer_cnt + 1;

                        -- Se ganhou: celebração dura 5 SEGUNDOS!
                        if win_reg = '1' then
                            if timer_cnt >= to_unsigned(WIN_PAYOUT_CYCLES - 1, timer_cnt'length) then
                                current_state <= S_WAIT_SPIN;
                            end if;
                        -- Se perdeu: transita após 1 segundo
                        else
                            if timer_cnt >= to_unsigned(LOSS_PAYOUT_CYCLES - 1, timer_cnt'length) then
                                current_state <= S_WAIT_SPIN;
                            end if;
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
    chaser_leds <= chaser_reg;

    spin_active   <= '1' when current_state = S_SPIN_REELS else '0';
    payout_active <= '1' when current_state = S_PAYOUT else '0';

    -- Pulso de piscar (blinker) para todos os 16 LEDs durante os 5 segundos de vitória
    blink_all_leds <= blink_state when (current_state = S_PAYOUT and win_reg = '1') else '0';

    ----------------------------------------------------------------------------
    -- Efeitos dos LEDs RGB LD16 e LD17:
    -- Durante a celebração de 5 segundos de vitória, mudam ciclicamente de cores!
    ----------------------------------------------------------------------------
    process(current_state, win_reg, rgb_step)
    begin
        if current_state = S_PAYOUT and win_reg = '1' then
            case rgb_step is
                -- Vermelho e Azul
                when 0 =>
                    rgb16_r <= '1'; rgb16_g <= '0'; rgb16_b <= '0';
                    rgb17_r <= '0'; rgb17_g <= '0'; rgb17_b <= '1';
                -- Verde e Amarelo
                when 1 =>
                    rgb16_r <= '0'; rgb16_g <= '1'; rgb16_b <= '0';
                    rgb17_r <= '1'; rgb17_g <= '1'; rgb17_b <= '0';
                -- Azul e Magenta
                when 2 =>
                    rgb16_r <= '0'; rgb16_g <= '0'; rgb16_b <= '1';
                    rgb17_r <= '1'; rgb17_g <= '0'; rgb17_b <= '1';
                -- Amarelo e Ciano
                when 3 =>
                    rgb16_r <= '1'; rgb16_g <= '1'; rgb16_b <= '0';
                    rgb17_r <= '0'; rgb17_g <= '1'; rgb17_b <= '1';
                -- Ciano e Branco
                when 4 =>
                    rgb16_r <= '0'; rgb16_g <= '1'; rgb16_b <= '1';
                    rgb17_r <= '1'; rgb17_g <= '1'; rgb17_b <= '1';
                -- Magenta e Verde
                when 5 =>
                    rgb16_r <= '1'; rgb16_g <= '0'; rgb16_b <= '1';
                    rgb17_r <= '0'; rgb17_g <= '1'; rgb17_b <= '0';
                -- Branco e Vermelho
                when others =>
                    rgb16_r <= '1'; rgb16_g <= '1'; rgb16_b <= '1';
                    rgb17_r <= '1'; rgb17_g <= '0'; rgb17_b <= '0';
            end case;
        elsif current_state = S_SPIN_REELS then
            -- Luz azul suave enquanto roda
            rgb16_r <= '0'; rgb16_g <= '0'; rgb16_b <= '1';
            rgb17_r <= '0'; rgb17_g <= '0'; rgb17_b <= '1';
        else
            -- Apagados em repouso
            rgb16_r <= '0'; rgb16_g <= '0'; rgb16_b <= '0';
            rgb17_r <= '0'; rgb17_g <= '0'; rgb17_b <= '0';
        end if;
    end process;

    with current_state select
        fsm_state_code <= "000" when S_WAIT_SPIN,
                          "001" when S_DEDUCT_BET,
                          "010" when S_SPIN_REELS,
                          "011" when S_CHECK_RESULT,
                          "100" when S_PAYOUT,
                          "111" when others;

end Behavioral;
