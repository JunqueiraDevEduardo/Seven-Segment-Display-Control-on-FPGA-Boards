----------------------------------------------------------------------------
-- top.vhd
-- Módulo de Topo da Slot Machine Adaptativa na Nexys 4 DDR
-- Layout visual inspirado no projeto DE2 Board Slot Machine (CPE 100L)
-- e motor adaptativo do artigo IEEE 2025.
--
-- Disposição visual nos 8 Displays de 7 Segmentos:
--   [AN7 AN6] = CRÉDITOS DO JOGADOR (ex: 50, 49... exatamente como HEX7 HEX6)
--   [AN5 AN4] = LIMIAR DINÂMICO IA (ex: 50, 92... como HEX5 HEX4)
--   [AN3 AN2 AN1 AN0] = OS 4 CARRETÉIS DA SLOT MACHINE (ex: 7 7 7 7 como HEX3..HEX0)
----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top is
    generic (
        SIM_SPEEDUP : boolean := false
    );
    port (
        clk  : in  STD_LOGIC;                                  -- 100 MHz (E3)
        btnc : in  STD_LOGIC;                                  -- SPIN (N17)
        btnu : in  STD_LOGIC;                                  -- RESET (M18)
        sw   : in  STD_LOGIC_VECTOR(15 downto 0);              -- Switches
        led  : out STD_LOGIC_VECTOR(15 downto 0);              -- LEDs
        an   : out STD_LOGIC_VECTOR(7 downto 0);               -- Ânodos (AN7..AN0)
        seg  : out STD_LOGIC_VECTOR(6 downto 0);               -- Cátodos (CA..CG)
        dp   : out STD_LOGIC                                   -- Ponto Decimal
    );
end top;

architecture Behavioral of top is

    -- Sinais de botões debounced e pulsos de borda
    signal btnc_db       : STD_LOGIC;
    signal btnu_db       : STD_LOGIC;
    signal btnc_prev     : STD_LOGIC := '0';
    signal btn_spin_pulse: STD_LOGIC := '0';

    -- Sinais do LFSR (PRNG)
    signal rand_100      : integer range 0 to 99;
    signal rand_byte     : STD_LOGIC_VECTOR(7 downto 0);
    signal rand_reel1    : unsigned(3 downto 0);
    signal rand_reel2    : unsigned(3 downto 0);
    signal rand_reel3    : unsigned(3 downto 0);
    signal rand_reel4    : unsigned(3 downto 0);

    -- Sinais do Controlador de Limiar Adaptativo
    signal threshold_val : integer range 0 to 99;
    signal threshold_vec : STD_LOGIC_VECTOR(7 downto 0);
    signal spins_count   : integer range 0 to 99;
    signal wins_count    : integer range 0 to 99;

    -- Sinais da FSM da Slot Machine
    signal disp_reel1    : unsigned(3 downto 0);
    signal disp_reel2    : unsigned(3 downto 0);
    signal disp_reel3    : unsigned(3 downto 0);
    signal disp_reel4    : unsigned(3 downto 0);
    signal credits_val   : integer range 0 to 99;
    signal led_win_s     : STD_LOGIC;
    signal spin_active_s : STD_LOGIC;
    signal payout_act_s  : STD_LOGIC;
    signal update_tick_s : STD_LOGIC;
    signal last_win_s    : STD_LOGIC;
    signal led_effects_s : STD_LOGIC_VECTOR(6 downto 0);
    signal fsm_code_s    : STD_LOGIC_VECTOR(2 downto 0);

    -- Sinais para o Multiplexador dos 8 Displays
    signal digits_bus    : STD_LOGIC_VECTOR(31 downto 0);
    signal dp_bus        : STD_LOGIC_VECTOR(7 downto 0);

    function get_debounce_const return integer is
    begin
        if SIM_SPEEDUP then
            return 5;
        else
            return 999999; -- ~10 ms @ 100 MHz
        end if;
    end function;

    constant DEBOUNCE_VAL : integer := get_debounce_const;

    function get_bcd(val : integer; is_tens : boolean) return std_logic_vector is
        variable d : integer range 0 to 9;
    begin
        if is_tens then
            d := (val / 10) mod 10;
        else
            d := val mod 10;
        end if;
        return std_logic_vector(to_unsigned(d, 4));
    end function;

begin

    ----------------------------------------------------------------------------
    -- 1. Debouncers para BTNC (SPIN) e BTNU (RESET)
    ----------------------------------------------------------------------------
    u_debounce_spin: entity work.debounce
        generic map (DEBOUNCE_CONST => DEBOUNCE_VAL)
        port map (clk => clk, input => btnc, output => btnc_db);

    u_debounce_reset: entity work.debounce
        generic map (DEBOUNCE_CONST => DEBOUNCE_VAL)
        port map (clk => clk, input => btnu, output => btnu_db);

    process(clk)
    begin
        if rising_edge(clk) then
            btnc_prev <= btnc_db;
            if btnc_db = '1' and btnc_prev = '0' then
                btn_spin_pulse <= '1';
            else
                btn_spin_pulse <= '0';
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- 2. Gerador Pseudo-Aleatório LFSR de 16-bit
    ----------------------------------------------------------------------------
    u_lfsr: entity work.lfsr_prng
        port map (
            clk        => clk,
            reset      => btnu_db,
            enable     => '1',
            rand_100   => rand_100,
            rand_byte  => rand_byte,
            rand_reel1 => rand_reel1,
            rand_reel2 => rand_reel2,
            rand_reel3 => rand_reel3,
            rand_reel4 => rand_reel4
        );

    ----------------------------------------------------------------------------
    -- 3. Controlador Dinâmico do Limiar (Artigo IEEE 2025)
    ----------------------------------------------------------------------------
    u_threshold_ctrl: entity work.adaptive_threshold_ctrl
        generic map (
            DEFAULT_THRESH => 50,
            MIN_THRESH     => 15,
            MAX_THRESH     => 95,
            STEP           => 7
        )
        port map (
            clk           => clk,
            reset         => btnu_db,
            update_tick   => update_tick_s,
            is_win        => last_win_s,
            load_sw       => sw(15),           -- SW15: Carga manual
            sw_threshold  => sw(7 downto 0),   -- SW7..0: Limiar manual
            threshold_val => threshold_val,
            threshold_vec => threshold_vec,
            spins_count   => spins_count,
            wins_count    => wins_count
        );

    ----------------------------------------------------------------------------
    -- 4. FSM da Slot Machine (4 Carretéis Sequenciais e Celebração)
    ----------------------------------------------------------------------------
    u_fsm: entity work.slot_machine_fsm
        generic map (
            SIM_SPEEDUP => SIM_SPEEDUP
        )
        port map (
            clk                   => clk,
            reset                 => btnu_db,
            btn_spin_pulse        => btn_spin_pulse,
            current_threshold     => threshold_val,
            rand_100              => rand_100,
            rand_reel1            => rand_reel1,
            rand_reel2            => rand_reel2,
            rand_reel3            => rand_reel3,
            rand_reel4            => rand_reel4,
            disp_reel1            => disp_reel1,
            disp_reel2            => disp_reel2,
            disp_reel3            => disp_reel3,
            disp_reel4            => disp_reel4,
            credits_out           => credits_val,
            led_win               => led_win_s,
            spin_active           => spin_active_s,
            payout_active         => payout_act_s,
            update_threshold_tick => update_tick_s,
            last_was_win          => last_win_s,
            led_effects           => led_effects_s,
            fsm_state_code        => fsm_code_s
        );

    ----------------------------------------------------------------------------
    -- 5. Disposição nos 8 Displays de 7 Segmentos (Fiel à Altera DE2)
    --
    --   [AN7 AN6]         : CRÉDITOS DO JOGADOR (ex: 50, 49)
    --   [AN5 AN4]         : LIMIAR DINÂMICO IA  (ex: 50, 92)
    --   [AN3 AN2 AN1 AN0] : OS 4 CARRETÉIS (Reel 4, Reel 3, Reel 2, Reel 1)
    ----------------------------------------------------------------------------
    digits_bus(31 downto 28) <= get_bcd(credits_val, true);     -- AN7: Dezena dos Créditos
    digits_bus(27 downto 24) <= get_bcd(credits_val, false);    -- AN6: Unidade dos Créditos
    digits_bus(23 downto 20) <= get_bcd(threshold_val, true);   -- AN5: Dezena do Limiar
    digits_bus(19 downto 16) <= get_bcd(threshold_val, false);  -- AN4: Unidade do Limiar
    digits_bus(15 downto 12) <= std_logic_vector(disp_reel4);   -- AN3: Carretel 4
    digits_bus(11 downto 8)  <= std_logic_vector(disp_reel3);   -- AN2: Carretel 3
    digits_bus(7 downto 4)   <= std_logic_vector(disp_reel2);   -- AN1: Carretel 2
    digits_bus(3 downto 0)   <= std_logic_vector(disp_reel1);   -- AN0: Carretel 1

    -- Pontos decimais delimitadores entre os blocos (Créditos . Limiar . Carretéis):
    dp_bus <= "10101111";

    -- Controlador de varrimento dos 8 displays
    u_disp_mux: entity work.disp_mux
        port map (
            clk    => clk,
            digits => digits_bus,
            dp_in  => dp_bus,
            an     => an,
            seg    => seg,
            dp     => dp
        );

    ----------------------------------------------------------------------------
    -- 6. Mapeamento dos 16 LEDs da Nexys-4 DDR
    ----------------------------------------------------------------------------
    -- LEDs 7..0: Limiar atual em binário (leds_threshold conforme artigo)
    led(7 downto 0) <= threshold_vec;

    -- LEDs 14..8: Efeitos visuais dinâmicos (Chaser em rotação / Festa no Jackpot)
    led(14 downto 8) <= led_effects_s when (spin_active_s = '1' or payout_act_s = '1')
                        else ("0000" & fsm_code_s);

    -- LED 15: Indicador de Vitória (led_win)
    led(15) <= led_win_s;

end Behavioral;
