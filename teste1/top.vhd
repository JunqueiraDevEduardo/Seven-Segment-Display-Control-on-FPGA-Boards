----------------------------------------------------------------------------
-- top.vhd
-- Módulo de Topo da Slot Machine na Nexys 4 DDR
-- Configuração 3 + 3 + 2 (6 Carretéis de Slot Machine + 2 Dígitos de Créditos)
--
-- Regras de Jogo:
--   - Perde nos dois trios: -5 Créditos
--   - Ganha num trio: +10 Créditos
--   - Ganha nos dois trios: +15 Créditos
--
-- Efeitos Visuais ao Ganhar:
--   - Celebração de 5 SEGUNDOS
--   - Todas as luzes da FPGA (LEDs 15..0) a piscar em uníssono (Blinker ~4 Hz)
--   - LEDs RGB LD16 e LD17 a alternar entre cores vivas
----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top is
    generic (
        SIM_SPEEDUP : boolean := false
    );
    port (
        clk     : in  STD_LOGIC;                               -- 100 MHz (E3)
        btnc    : in  STD_LOGIC;                               -- SPIN (N17)
        btnu    : in  STD_LOGIC;                               -- RESET (M18)
        sw      : in  STD_LOGIC_VECTOR(15 downto 0);           -- Switches
        led     : out STD_LOGIC_VECTOR(15 downto 0);           -- 16 LEDs da placa
        an      : out STD_LOGIC_VECTOR(7 downto 0);            -- Ânodos (AN7..AN0)
        seg     : out STD_LOGIC_VECTOR(6 downto 0);            -- Cátodos (CA..CG)
        dp      : out STD_LOGIC;                               -- Ponto Decimal
        led16_r : out STD_LOGIC;                               -- LD16 Vermelho (N15)
        led16_g : out STD_LOGIC;                               -- LD16 Verde (M16)
        led16_b : out STD_LOGIC;                               -- LD16 Azul (R12)
        led17_r : out STD_LOGIC;                               -- LD17 Vermelho (N16)
        led17_g : out STD_LOGIC;                               -- LD17 Verde (R11)
        led17_b : out STD_LOGIC                                -- LD17 Azul (G14)
    );
end top;

architecture Behavioral of top is

    -- Sinais de botões debounced e pulsos de borda
    signal btnc_db        : STD_LOGIC;
    signal btnu_db        : STD_LOGIC;
    signal btnc_prev      : STD_LOGIC := '0';
    signal btn_spin_pulse : STD_LOGIC := '0';

    -- Sinais do LFSR (PRNG) de 16-bit
    signal rand_val       : unsigned(7 downto 0);
    signal rand_reel1     : unsigned(3 downto 0);
    signal rand_reel2     : unsigned(3 downto 0);
    signal rand_reel3     : unsigned(3 downto 0);
    signal rand_reel4     : unsigned(3 downto 0);
    signal rand_reel5     : unsigned(3 downto 0);
    signal rand_reel6     : unsigned(3 downto 0);

    -- Sinais da FSM da Slot Machine (6 Carretéis)
    signal disp_reel1     : unsigned(3 downto 0);
    signal disp_reel2     : unsigned(3 downto 0);
    signal disp_reel3     : unsigned(3 downto 0);
    signal disp_reel4     : unsigned(3 downto 0);
    signal disp_reel5     : unsigned(3 downto 0);
    signal disp_reel6     : unsigned(3 downto 0);
    signal credits_val    : integer range 0 to 99;
    signal led_win_s      : STD_LOGIC;
    signal spin_active_s  : STD_LOGIC;
    signal payout_act_s   : STD_LOGIC;
    signal blink_all_s    : STD_LOGIC;
    signal chaser_leds_s  : STD_LOGIC_VECTOR(6 downto 0);
    signal fsm_code_s     : STD_LOGIC_VECTOR(2 downto 0);

    -- Sinais para o Multiplexador dos 8 Displays
    signal digits_bus     : STD_LOGIC_VECTOR(31 downto 0);
    signal dp_bus         : STD_LOGIC_VECTOR(7 downto 0);

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
            rand_val   => rand_val,
            rand_reel1 => rand_reel1,
            rand_reel2 => rand_reel2,
            rand_reel3 => rand_reel3,
            rand_reel4 => rand_reel4,
            rand_reel5 => rand_reel5,
            rand_reel6 => rand_reel6
        );

    ----------------------------------------------------------------------------
    -- 3. FSM da Slot Machine (6 Carretéis com Celebração de 5 Segundos)
    ----------------------------------------------------------------------------
    u_fsm: entity work.slot_machine_fsm
        generic map (
            SIM_SPEEDUP => SIM_SPEEDUP
        )
        port map (
            clk            => clk,
            reset          => btnu_db,
            btn_spin_pulse => btn_spin_pulse,
            rand_val       => rand_val,
            rand_reel1     => rand_reel1,
            rand_reel2     => rand_reel2,
            rand_reel3     => rand_reel3,
            rand_reel4     => rand_reel4,
            rand_reel5     => rand_reel5,
            rand_reel6     => rand_reel6,
            disp_reel1     => disp_reel1,
            disp_reel2     => disp_reel2,
            disp_reel3     => disp_reel3,
            disp_reel4     => disp_reel4,
            disp_reel5     => disp_reel5,
            disp_reel6     => disp_reel6,
            credits_out    => credits_val,
            led_win        => led_win_s,
            spin_active    => spin_active_s,
            payout_active  => payout_act_s,
            blink_all_leds => blink_all_s,
            chaser_leds    => chaser_leds_s,
            rgb16_r        => led16_r,
            rgb16_g        => led16_g,
            rgb16_b        => led16_b,
            rgb17_r        => led17_r,
            rgb17_g        => led17_g,
            rgb17_b        => led17_b,
            fsm_state_code => fsm_code_s
        );

    ----------------------------------------------------------------------------
    -- 4. Disposição nos 8 Displays: 3 Carretéis + 3 Carretéis + 2 Créditos
    --
    --   [AN7 AN6 AN5] : 1º Trio de Carretéis (Reel 1, Reel 2, Reel 3)
    --   [AN4 AN3 AN2] : 2º Trio de Carretéis (Reel 4, Reel 5, Reel 6)
    --   [AN1 AN0]     : Os Últimos 2 Dígitos para Créditos (Dezenas, Unidades)
    ----------------------------------------------------------------------------
    digits_bus(31 downto 28) <= std_logic_vector(disp_reel1);   -- AN7: Carretel 1
    digits_bus(27 downto 24) <= std_logic_vector(disp_reel2);   -- AN6: Carretel 2
    digits_bus(23 downto 20) <= std_logic_vector(disp_reel3);   -- AN5: Carretel 3

    digits_bus(19 downto 16) <= std_logic_vector(disp_reel4);   -- AN4: Carretel 4
    digits_bus(15 downto 12) <= std_logic_vector(disp_reel5);   -- AN3: Carretel 5
    digits_bus(11 downto 8)  <= std_logic_vector(disp_reel6);   -- AN2: Carretel 6

    digits_bus(7 downto 4)   <= get_bcd(credits_val, true);     -- AN1: Dezena dos Créditos
    digits_bus(3 downto 0)   <= get_bcd(credits_val, false);    -- AN0: Unidade dos Créditos

    -- Pontos decimais delimitadores entre os blocos (ativo em baixo '0'):
    -- Ponto após AN5 e após AN2: "777. 777. 50"
    dp_bus <= "11011011";

    -- Controlador de varrimento para os 8 displays da placa
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
    -- 5. Mapeamento dos 16 LEDs da Nexys-4 DDR
    --
    -- Ao ganhar: TODAS AS 16 LUZES piscam em uníssono (Blinker) durante 5 segundos!
    -- Durante o giro: LEDs 14..8 fazem a corrida de luzes (*chaser*).
    -- Em repouso: LEDs 7..0 mostram a barra binária dos créditos.
    ----------------------------------------------------------------------------
    process(payout_act_s, led_win_s, blink_all_s, spin_active_s, chaser_leds_s, credits_val)
    begin
        if payout_act_s = '1' and led_win_s = '1' then
            -- TODAS AS 16 LUZES A PISCAR EM UNÍSSONO!
            if blink_all_s = '1' then
                led <= (others => '1');
            else
                led <= (others => '0');
            end if;
        elsif spin_active_s = '1' then
            -- Luzes a correr nos LEDs 14..8
            led(15) <= '0';
            led(14 downto 8) <= chaser_leds_s;
            led(7 downto 0)  <= std_logic_vector(to_unsigned(credits_val, 8));
        else
            -- Repouso
            led(15 downto 8) <= (others => '0');
            led(7 downto 0)  <= std_logic_vector(to_unsigned(credits_val, 8));
        end if;
    end process;

end Behavioral;
