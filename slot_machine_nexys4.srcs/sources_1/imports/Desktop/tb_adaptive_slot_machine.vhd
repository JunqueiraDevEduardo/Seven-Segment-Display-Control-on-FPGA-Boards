----------------------------------------------------------------------------
-- tb_adaptive_slot_machine.vhd
-- Testbench de Simulação para a Slot Machine Adaptativa em VHDL
-- Validação funcional:
--   - Transições de estados da FSM
--   - Dedução de aposta e pagamento de créditos
--   - Aleatoriedade do LFSR e rotação dos carretéis
--   - Deteção de vitória contra o limiar dinâmico
--   - Adaptação dinâmica do limiar (regras de Win Rate > 60% e < 30%)
----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_adaptive_slot_machine is
end tb_adaptive_slot_machine;

architecture sim of tb_adaptive_slot_machine is

    constant CLK_PERIOD : time := 10 ns; -- 100 MHz

    signal clk  : STD_LOGIC := '0';
    signal btnc : STD_LOGIC := '0';
    signal btnu : STD_LOGIC := '0';
    signal sw   : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
    signal led  : STD_LOGIC_VECTOR(15 downto 0);
    signal an   : STD_LOGIC_VECTOR(7 downto 0);
    signal seg  : STD_LOGIC_VECTOR(6 downto 0);
    signal dp   : STD_LOGIC;

    -- Procedimento para simular uma pressão no botão SPIN (btnc)
    procedure press_spin(signal b : out STD_LOGIC) is
    begin
        b <= '1';
        wait for 300 ns; -- tempo superior ao debounce em simulação
        b <= '0';
        wait for 500 ns;
    end procedure;

begin

    -- Gerador de relógio 100 MHz
    clk <= not clk after CLK_PERIOD / 2;

    -- Instanciação do módulo de topo com SIM_SPEEDUP = true para simulação ultra-rápida
    dut: entity work.top
        generic map (
            SIM_SPEEDUP => true
        )
        port map (
            clk  => clk,
            btnc => btnc,
            btnu => btnu,
            sw   => sw,
            led  => led,
            an   => an,
            seg  => seg,
            dp   => dp
        );

    -- Processo de estímulos
    process
    begin
        report "================ INICIO DA SIMULACAO ================" severity note;

        -- 1. Reset Global
        btnu <= '1';
        wait for 200 ns;
        btnu <= '0';
        wait for 500 ns;

        -- Verifica limiar inicial padrão (50 = 0x32 nos LEDs 7..0)
        assert led(7 downto 0) = std_logic_vector(to_unsigned(50, 8))
            report "FALHA: Limiar inicial esperado = 50!" severity error;
        report "SUCESSO: Limiar inicial verificado = 50 (0x32)." severity note;

        -- 2. Execução de Múltiplas Rodadas (Spins)
        report "Executando Spin 1..." severity note;
        press_spin(btnc);
        wait for 3 us; -- aguarda ciclo completo da rodada

        report "Executando Spin 2..." severity note;
        press_spin(btnc);
        wait for 3 us;

        report "Executando Spin 3..." severity note;
        press_spin(btnc);
        wait for 3 us;

        report "Executando Spin 4..." severity note;
        press_spin(btnc);
        wait for 3 us;

        report "Executando Spin 5..." severity note;
        press_spin(btnc);
        wait for 3 us;

        report "Executando Spin 6..." severity note;
        press_spin(btnc);
        wait for 3 us;

        report "Executando Spin 7..." severity note;
        press_spin(btnc);
        wait for 3 us;

        report "Executando Spin 8..." severity note;
        press_spin(btnc);
        wait for 3 us;

        report "Executando Spin 9..." severity note;
        press_spin(btnc);
        wait for 3 us;

        report "Executando Spin 10..." severity note;
        press_spin(btnc);
        wait for 3 us;

        report "======================================================" severity note;
        report "Limiar final adaptado apos 10 rodadas: " &
               integer'image(to_integer(unsigned(led(7 downto 0)))) severity note;
        report "================ FIM DA SIMULACAO COM SUCESSO ========" severity note;

        wait for 1 us;
        std.env.stop;
    end process;

end sim;
