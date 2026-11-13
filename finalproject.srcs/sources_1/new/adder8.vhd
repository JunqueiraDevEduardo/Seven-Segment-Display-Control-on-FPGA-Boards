----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 13.11.2026 21:20:23
-- Design Name: 
-- Module Name: adder8 - Behavioral
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

entity adder8 is
 Port (
 a:in STD_LOGIC_VECTOR(7 downto 0);
 b:in STD_LOGIC_VECTOR(7 downto 0);
 sum:out STD_LOGIC_VECTOR(8 downto 0) --9 bits inclui o array
  );
end adder8;

architecture Behavioral of adder8 is

begin
    sum <= std_logic_vector(unsigned('0'& a)+unsigned('0'& b));

end Behavioral;
