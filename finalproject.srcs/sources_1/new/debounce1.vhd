library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity debounce is
    generic (
        DEBOUNCE_CONST : integer := 999999  -- ~10 ms @ 100 MHz
    );
    port (
        clk    : in  STD_LOGIC;
        input  : in  STD_LOGIC;
        output : out STD_LOGIC
    );
end debounce;

architecture Behavioral of debounce is
    type state_t is (idle, detect_high, wait_low, detect_low);
    signal state   : state_t := idle;
    signal counter : unsigned(19 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            case state is

                when idle =>
                    output  <= '0';
                    counter <= (others => '0');
                    if input = '1' then
                        state <= detect_high;
                    end if;

                when detect_high =>
                    output <= '0';
                    if input = '0' then
                        state   <= idle;
                        counter <= (others => '0');
                    elsif counter = to_unsigned(DEBOUNCE_CONST, counter'length) then
                        state   <= wait_low;
                        counter <= (others => '0');
                    else
                        counter <= counter + 1;
                    end if;

                when wait_low =>
                    output  <= '1';
                    counter <= (others => '0');
                    if input = '0' then
                        state <= detect_low;
                    end if;

                when detect_low =>
                    output <= '1';
                    if input = '1' then
                        state   <= wait_low;
                        counter <= (others => '0');
                    elsif counter = to_unsigned(DEBOUNCE_CONST, counter'length) then
                        state   <= idle;
                        counter <= (others => '0');
                    else
                        counter <= counter + 1;
                    end if;

            end case;
        end if;
    end process;
end Behavioral;