----------------------------------------------------------------------------
-- disp_mux.vhd
-- Controlador de varrimento (scanning) para os 8 dígitos de 7 segmentos
-- do Nexys4 DDR. Mostra, por persistência de visão, 8 valores de 4 bits
-- em simultâneo, partilhando o único descodificador hex_to_7seg.
--
-- digits(3 downto 0)   -> dígito 0 (AN0)
-- digits(7 downto 4)   -> dígito 1 (AN1)
-- ...
-- digits(31 downto 28) -> dígito 7 (AN7)
--
-- Frequência de refrescamento total ~ 100MHz / 2^17 / 8 ≈ 95 Hz
-- (dentro da gama 60Hz-1kHz recomendada no manual da placa)
----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity disp_mux is
    port (
        clk    : in  STD_LOGIC;                                  -- 100 MHz
        digits : in  STD_LOGIC_VECTOR(31 downto 0);              -- 8 nibbles
        dp_in  : in  STD_LOGIC_VECTOR(7 downto 0) := (others => '1'); -- '0' acende o DP do dígito
        an     : out STD_LOGIC_VECTOR(7 downto 0);               -- ativo a '0'
        seg    : out STD_LOGIC_VECTOR(6 downto 0);               -- CA..CG, ativo a '0'
        dp     : out STD_LOGIC
    );
end disp_mux;

architecture Behavioral of disp_mux is
    signal refresh_cnt : unsigned(19 downto 0) := (others => '0');
    signal digit_sel   : STD_LOGIC_VECTOR(2 downto 0);
    signal hex_nibble  : STD_LOGIC_VECTOR(3 downto 0);
begin

    -- contador livre: os 3 bits mais significativos selecionam o dígito ativo
    process(clk)
    begin
        if rising_edge(clk) then
            refresh_cnt <= refresh_cnt + 1;
        end if;
    end process;

    digit_sel <= std_logic_vector(refresh_cnt(19 downto 17));

    -- escolhe o nibble do dígito atualmente ativo
    with digit_sel select
        hex_nibble <= digits(3 downto 0)   when "000",
                      digits(7 downto 4)   when "001",
                      digits(11 downto 8)  when "010",
                      digits(15 downto 12) when "011",
                      digits(19 downto 16) when "100",
                      digits(23 downto 20) when "101",
                      digits(27 downto 24) when "110",
                      digits(31 downto 28) when others;

    -- descodificador instanciado uma única vez (reutilização de blocos)
    hex_decoder: entity work.hex_to_7seg
        port map (
            hex => hex_nibble,
            seg => seg
        );

    -- ativa o anodo do dígito selecionado (one-hot, ativo a '0')
    with digit_sel select
        an <= "11111110" when "000",
              "11111101" when "001",
              "11111011" when "010",
              "11110111" when "011",
              "11101111" when "100",
              "11011111" when "101",
              "10111111" when "110",
              "01111111" when others;

    with digit_sel select
        dp <= dp_in(0) when "000",
              dp_in(1) when "001",
              dp_in(2) when "010",
              dp_in(3) when "011",
              dp_in(4) when "100",
              dp_in(5) when "101",
              dp_in(6) when "110",
              dp_in(7) when others;

end Behavioral;