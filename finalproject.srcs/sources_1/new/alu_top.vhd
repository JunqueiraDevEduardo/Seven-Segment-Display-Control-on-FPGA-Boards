----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 13.11.2026 21:40:35
-- Design Name: 
-- Module Name: alu_top - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity alu_top is
  Port (clk:in STD_LOGIC;
        btnc:in STD_LOGIC;
        sw:in STD_LOGIC_VECTOR(15 downto 0);
        led:out STD_LOGIC_VECTOR(15 downto 0);
        an:out STD_LOGIC_VECTOR(7 downto 0);
        seg:out STD_LOGIC_VECTOR(6 downto 0);
        dp:out STD_LOGIC
        
        
         );
        
end alu_top;

architecture Behavioral of alu_top is

    component mult_gen_0
        port(
            CLK:in STD_LOGIC;
            A:in STD_LOGIC_VECTOR(7 downto 0);
            B:in STD_LOGIC_VECTOR(7 downto 0);
            P:out STD_LOGIC_VECTOR(15 downto 0)
        
        );
    end component;
    
    signal a, b :STD_LOGIC_VECTOR(7 downto 0);
    signal sum9 :STD_LOGIC_VECTOR(8 downto 0);
    signal prod16:STD_LOGIC_VECTOR(15 downto 0);
    signal result :STD_LOGIC_VECTOR(15 downto 0);
    signal btn_db:STD_LOGIC;
    signal btn_prev:STD_LOGIC:='0';
    signal mode :STD_LOGIC:='0'; -- '0' = SOMA(DEFAULT), '1'=multiplicação
    signal digits:STD_LOGIC_VECTOR(31 downto 0);    
begin

a<=sw(7 downto 0);
b<=sw(15 downto 8);

--SOMADOR
u_add:entity work.adder8
    port map(a=>a,b=>b,sum=>sum9);
    
--MULTIPLICADOR (IP Xilinx)
U_mult:mult_gen_0
    port map (CLK=>clk,A=>a,B=>b,P=>prod16);
        -- Debounce do BTNC
    u_debounce: entity work.debounce
        port map (clk => clk, input => btnc, output => btn_db);
--Alterna o modo no flanco ascendente do botão
process(clk)
begin
    if rising_edge(clk) then
        btn_prev <= btn_db;
        if btn_db ='1' and btn_prev ='0' then
            mode<= not mode;
        end if;
        end if;
end process;

--Seleção do resultado
result<="0000000" & sum9 when mode ='0' else prod16;

--LEDs:LED0=LSB
led<=result;

--Displays: AN7..AN6=b,AN5..AN4=a,AN3..AN0=resultado
digits<=b&a&result;

u_disp:entity work.disp_mux
    port map(
    clk=>clk,
    digits=>digits,
    dp_in=>"11111111",
    an=>an,
    seg=>seg,
    dp=>dp
    );

 end Behavioral;
