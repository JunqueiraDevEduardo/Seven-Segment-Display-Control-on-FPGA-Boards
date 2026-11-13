=====================================================================
FINALPROJECT - ALU de 8 bits na Nexys4 DDR (Vivado 2025.1, VHDL)
=====================================================================

O QUE FAZ NA PLACA
---------------------------------------------------------------------
Pequena ALU (Unidade Aritmetica e Logica) com duas entradas de 8 bits
que realiza SOMA e MULTIPLICACAO. O resultado aparece nos LEDs e nos
displays de 7 segmentos.

ENTRADAS
  - a = SW0..SW7   (SW0 = bit menos significativo)
  - b = SW8..SW15  (SW8 = bit menos significativo)
  - BTNC           (alterna entre soma e multiplicacao)

SAIDAS
  - LED0..LED15: resultado em binario (LED0 = LSB)
  - Displays de 7 segmentos (8 digitos, em hexadecimal):

        AN7 AN6 | AN5 AN4 | AN3 AN2 AN1 AN0
          b     |    a    |   resultado (4 digitos hex)

FUNCIONAMENTO
  - Ao ligar/programar, o modo por defeito e SOMA (a + b).
  - Cada pressao em BTNC alterna: soma -> multiplicacao -> soma ...
  - O botao passa por um filtro de debounce (~10 ms) e e detetado o
    flanco ascendente, por isso cada pressao muda o modo uma unica vez.
  - Soma: resultado de 9 bits (max. 255 + 255 = 510), usa LED0..LED8;
    os restantes LEDs ficam apagados.
  - Multiplicacao: resultado de 16 bits (max. 255 x 255 = 65025),
    usa LED0..LED15.
  - O multiplicador e um IP da Xilinx (Multiplier 12.0, unsigned 8x8,
    saida P[15:0]) com alguns ciclos de latencia; a 100 MHz isto e
    imperceptivel.

EXEMPLO
  SW0..7 = 00001010 (a = 10 = 0x0A), SW8..15 = 00000011 (b = 3 = 0x03)
    - Soma:           13 -> LEDs ...0000 0000 0000 1101
                           display: 03 0A 000D
    - Multiplicacao:  30 -> LEDs ...0000 0000 0001 1110
                           display: 03 0A 001E

ESTRUTURA DO PROJETO (VHDL)
  alu_top.vhd      Modulo de topo: liga tudo e escolhe soma/mult.
  adder8.vhd       Somador de 8 bits com saida de 9 bits (carry).
  mult_gen_0       IP Xilinx Multiplier (unsigned 8x8 -> 16 bits).
  debounce.vhd     FSM de debounce do botao (10 ms @ 100 MHz).
  disp_mux.vhd     Multiplexagem dos 8 digitos de 7 segmentos
                   (refresh ~95 Hz, persistencia de visao).
  hex_to_7seg.vhd  Descodificador hex (0-F) -> segmentos (ativo a '0').
  alu.xdc          Constraints: pinos da Nexys4 DDR (clk 100 MHz,
                   switches, LEDs, BTNC, segmentos e anodos).

DIAGRAMA DE BLOCOS
  SW[7:0]  = a --+--> adder8 ------> sum (9 bits) --+
                 |                                  +--> MUX (modo)
  SW[15:8] = b --+--> mult_gen_0 --> prod (16 bits)-+       |
                                                            v
  BTNC --> debounce --> flanco --> toggle (modo)     result (16 bits)
                                                       |         |
                                                       v         v
                                                     LED[15:0]  disp_mux
                                                                (b & a & result)
                                                                  -> 7 seg

COMO USAR
  1. Abrir o projeto no Vivado e confirmar que alu_top e o top.
  2. Run Synthesis -> Run Implementation -> Generate Bitstream.
  3. Open Hardware Manager -> Auto Connect -> Program Device.
  4. Mexer nos switches para definir a e b; ver o resultado nos LEDs
     e nos displays. Carregar em BTNC para alternar soma/multiplicacao.

NOTAS
  - Os displays da Nexys4 DDR sao de anodo comum: segmento aceso = '0'.
  - Os anodos (an) tambem sao ativos a '0'.
  - Os ficheiros debounce, disp_mux e hex_to_7seg foram reutilizados
    do projeto anterior (contador hexadecimal).
=====================================================================
