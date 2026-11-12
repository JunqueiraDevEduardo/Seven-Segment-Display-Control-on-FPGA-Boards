----------------------------------------------------------------------------
-- hex_to_7seg.vhd
-- Descodificador combinacional: 4 bits (0-F) -> padrão de 7 segmentos
-- Nexys4 DDR usa displays de ANODO COMUM -> segmento aceso = '0'
-- Ordem do bus seg: (6)=a (5)=b (4)=c (3)=d (2)=e (1)=f (0)=g
----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity hex_to_7seg is
    port (
        hex : in  STD_LOGIC_VECTOR(3 downto 0);  -- valor a mostrar (0x0 a 0xF)
        seg : out STD_LOGIC_VECTOR(6 downto 0)   -- a,b,c,d,e,f,g (ativo a '0')
    );
end hex_to_7seg;

architecture Behavioral of hex_to_7seg is
begin
    process(hex)
    begin
        case hex is
            when "0000" => seg <= "0000001"; -- 0
            when "0001" => seg <= "1001111"; -- 1
            when "0010" => seg <= "0010010"; -- 2
            when "0011" => seg <= "0000110"; -- 3
            when "0100" => seg <= "1001100"; -- 4
            when "0101" => seg <= "0100100"; -- 5
            when "0110" => seg <= "0100000"; -- 6
            when "0111" => seg <= "0001111"; -- 7
            when "1000" => seg <= "0000000"; -- 8
            when "1001" => seg <= "0000100"; -- 9
            when "1010" => seg <= "0001000"; -- A
            when "1011" => seg <= "1100000"; -- b
            when "1100" => seg <= "0110001"; -- C
            when "1101" => seg <= "1000010"; -- d
            when "1110" => seg <= "0110000"; -- E
            when "1111" => seg <= "0111000"; -- F
            when others => seg <= "1111111"; -- apagado
        end case;
    end process;
end Behavioral;
