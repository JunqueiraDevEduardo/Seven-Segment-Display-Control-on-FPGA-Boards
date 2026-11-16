library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_disp_mux is
end tb_disp_mux;

architecture sim of tb_disp_mux is
    signal clk    : STD_LOGIC := '0';
    signal digits : STD_LOGIC_VECTOR(31 downto 0) := x"76543210";
    signal an     : STD_LOGIC_VECTOR(7 downto 0);
    signal seg    : STD_LOGIC_VECTOR(6 downto 0);
    signal dp     : STD_LOGIC;
begin
    clk <= not clk after 5 ns;  -- 100 MHz

    dut: entity work.disp_mux
        port map (clk => clk, digits => digits, an => an, seg => seg, dp => dp);

    process
    begin
        wait for 25 ms;  -- cerca de 2 varrimentos completos
        std.env.stop;
    end process;
end sim;
