----------------------------------------------------------------------------
-- lfsr_prng.vhd
-- Gerador Pseudo-Aleatório de 16 bits para Slot Machine de 6 Carretéis (3 + 3)
-- Polinómio maximal: x^16 + x^14 + x^13 + x^11 + 1 (taps: 15, 13, 12, 10).
----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity lfsr_prng is
    port (
        clk        : in  STD_LOGIC;
        reset      : in  STD_LOGIC;
        enable     : in  STD_LOGIC;
        rand_val   : out unsigned(7 downto 0);
        rand_reel1 : out unsigned(3 downto 0); -- Carretel 1 [0..9]
        rand_reel2 : out unsigned(3 downto 0); -- Carretel 2 [0..9]
        rand_reel3 : out unsigned(3 downto 0); -- Carretel 3 [0..9]
        rand_reel4 : out unsigned(3 downto 0); -- Carretel 4 [0..9]
        rand_reel5 : out unsigned(3 downto 0); -- Carretel 5 [0..9]
        rand_reel6 : out unsigned(3 downto 0)  -- Carretel 6 [0..9]
    );
end lfsr_prng;

architecture Behavioral of lfsr_prng is
    constant SEED : STD_LOGIC_VECTOR(15 downto 0) := x"ACE1";
    signal s_reg  : STD_LOGIC_VECTOR(15 downto 0) := SEED;
    signal feedback : STD_LOGIC;
begin

    feedback <= s_reg(15) xor s_reg(13) xor s_reg(12) xor s_reg(10);

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                s_reg <= SEED;
            elsif enable = '1' then
                s_reg <= s_reg(14 downto 0) & feedback;
            end if;
        end if;
    end process;

    rand_val <= unsigned(s_reg(7 downto 0));

    -- Extração de 6 dígitos independentes para os carretéis
    rand_reel1 <= to_unsigned(to_integer(unsigned(s_reg(3 downto 0))) mod 10, 4);
    rand_reel2 <= to_unsigned(to_integer(unsigned(s_reg(7 downto 4))) mod 10, 4);
    rand_reel3 <= to_unsigned(to_integer(unsigned(s_reg(11 downto 8))) mod 10, 4);
    rand_reel4 <= to_unsigned(to_integer(unsigned(s_reg(15 downto 12))) mod 10, 4);
    rand_reel5 <= to_unsigned((to_integer(unsigned(s_reg(5 downto 2))) + 3) mod 10, 4);
    rand_reel6 <= to_unsigned((to_integer(unsigned(s_reg(9 downto 6))) + 7) mod 10, 4);

end Behavioral;