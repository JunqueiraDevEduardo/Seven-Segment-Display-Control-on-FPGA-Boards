----------------------------------------------------------------------------
-- top.vhd
-- Módulo de topo: contador hexadecimal de 32 bits mostrado nos 8 dígitos
-- de 7 segmentos do Nexys4 DDR.
--
--   sw(0)  = '1' -> conta automaticamente (~5 Hz)
--   btnC         -> incrementa 1 vez por pressão (com debounce)
--   btnU         -> reset do contador a 0
----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top is
    port (
        clk  : in  STD_LOGIC;                      -- 100 MHz
        btnc : in  STD_LOGIC;                      -- botão central
        btnu : in  STD_LOGIC;                      -- botão de cima (reset)
        sw   : in  STD_LOGIC_VECTOR(0 downto 0);   -- switch 0
        an   : out STD_LOGIC_VECTOR(7 downto 0);
        seg  : out STD_LOGIC_VECTOR(6 downto 0);
        dp   : out STD_LOGIC
    );
end top;

architecture Behavioral of top is
    signal count    : unsigned(31 downto 0) := (others => '0');
    signal tick_cnt : unsigned(24 downto 0) := (others => '0');
    signal tick     : STD_LOGIC := '0';
    signal btn_db   : STD_LOGIC;
    signal btn_prev : STD_LOGIC := '0';
begin

    -- limpa o ruído mecânico do botão
    u_debounce: entity work.debounce
        port map (clk => clk, input => btnc, output => btn_db);

    -- varrimento dos 8 dígitos + descodificação
    u_disp: entity work.disp_mux
        port map (
            clk    => clk,
            digits => std_logic_vector(count),
            dp_in  => "11111111",   -- pontos decimais todos apagados
            an     => an,
            seg    => seg,
            dp     => dp
        );

    process(clk)
    begin
        if rising_edge(clk) then
            btn_prev <= btn_db;

            -- gera um pulso 'tick' de 1 ciclo a cada 20 000 000 ciclos (5 Hz)
            if tick_cnt = to_unsigned(19999999, tick_cnt'length) then
                tick_cnt <= (others => '0');
                tick     <= '1';
            else
                tick_cnt <= tick_cnt + 1;
                tick     <= '0';
            end if;

            if btnu = '1' then
                count <= (others => '0');
            elsif (btn_db = '1' and btn_prev = '0')      -- flanco ascendente do botão
               or (sw(0) = '1' and tick = '1') then      -- ou contagem automática
                count <= count + 1;
            end if;
        end if;
    end process;

end Behavioral;
