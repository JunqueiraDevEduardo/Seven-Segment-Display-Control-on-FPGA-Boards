----------------------------------------------------------------------------
-- adaptive_threshold_ctrl.vhd
-- Controlador Dinâmico do Limiar (Dynamic Threshold Controller)
-- Implementa a lógica adaptativa baseada no histórico de jogo descrita no artigo:
--   "Design and FPGA Realization of an Adaptive Slot Machine with Dynamic Threshold Control"
--
-- Equação do artigo:
--   Win Rate = (Number of Wins / Total Spins) * 100
-- Regras adaptativas:
--   - Se Win Rate > 60%: Aumenta o limiar (diminui a probabilidade de vitória futura)
--   - Se Win Rate < 30%: Diminui o limiar (aumenta a probabilidade de vitória futura)
--   - Inicialmente repousa em 50 (conforme Fig. 5 do artigo)
----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity adaptive_threshold_ctrl is
    generic (
        DEFAULT_THRESH : integer := 50;
        MIN_THRESH     : integer := 15;
        MAX_THRESH     : integer := 95;
        STEP           : integer := 7
    );
    port (
        clk           : in  STD_LOGIC;
        reset         : in  STD_LOGIC;
        update_tick   : in  STD_LOGIC;                      -- Pulso emitido no fim de cada jogada
        is_win        : in  STD_LOGIC;                      -- '1' se a jogada atual resultou em vitória
        load_sw       : in  STD_LOGIC;                      -- '1' força carregamento do valor dos switches
        sw_threshold  : in  STD_LOGIC_VECTOR(7 downto 0);   -- Valor inicial configurável via switches
        threshold_val : out integer range 0 to 99;          -- Valor numérico [0..99] para display
        threshold_vec : out STD_LOGIC_VECTOR(7 downto 0);   -- Vetor para leds_threshold(7 downto 0)
        spins_count   : out integer range 0 to 99;          -- Total de jogadas
        wins_count    : out integer range 0 to 99           -- Total de vitórias
    );
end adaptive_threshold_ctrl;

architecture Behavioral of adaptive_threshold_ctrl is
    signal current_thresh : integer range 0 to 99 := DEFAULT_THRESH;
    signal spins_reg      : integer range 0 to 99 := 0;
    signal wins_reg       : integer range 0 to 99 := 0;
begin

    process(clk)
        variable next_spins : integer range 0 to 100;
        variable next_wins  : integer range 0 to 100;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                current_thresh <= DEFAULT_THRESH;
                spins_reg      <= 0;
                wins_reg       <= 0;
            elsif load_sw = '1' then
                -- Carregamento manual através dos switches
                if to_integer(unsigned(sw_threshold)) <= MAX_THRESH and
                   to_integer(unsigned(sw_threshold)) >= MIN_THRESH then
                    current_thresh <= to_integer(unsigned(sw_threshold));
                else
                    current_thresh <= DEFAULT_THRESH;
                end if;
                spins_reg <= 0;
                wins_reg  <= 0;
            elsif update_tick = '1' then
                -- Incrementa registos de estatística
                if spins_reg < 99 then
                    next_spins := spins_reg + 1;
                else
                    next_spins := spins_reg;
                end if;

                if is_win = '1' and wins_reg < 99 then
                    next_wins := wins_reg + 1;
                else
                    next_wins := wins_reg;
                end if;

                spins_reg <= next_spins;
                wins_reg  <= next_wins;

                -- Avaliação do limiar adaptativo
                -- Para estabilidade estatística, avalia após pelo menos 2 jogadas
                if next_spins >= 2 then
                    -- Win Rate > 60%  <=>  (wins * 10) > (spins * 6)
                    if (next_wins * 10) > (next_spins * 6) then
                        if current_thresh + STEP <= MAX_THRESH then
                            current_thresh <= current_thresh + STEP;
                        else
                            current_thresh <= MAX_THRESH;
                        end if;

                    -- Win Rate < 30%  <=>  (wins * 10) < (spins * 3)
                    elsif (next_wins * 10) < (next_spins * 3) then
                        if current_thresh - STEP >= MIN_THRESH then
                            current_thresh <= current_thresh - STEP;
                        else
                            current_thresh <= MIN_THRESH;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    threshold_val <= current_thresh;
    threshold_vec <= std_logic_vector(to_unsigned(current_thresh, 8));
    spins_count   <= spins_reg;
    wins_count    <= wins_reg;

end Behavioral;
