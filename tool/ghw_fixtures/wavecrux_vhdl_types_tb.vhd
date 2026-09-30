-- WaveCrux GHW functional fixture source.
--
-- A self-driving VHDL-2008 testbench (no ports, no external stimulus) whose
-- internal signals deliberately exercise the VHDL-specific richness that the
-- GHW format carries and that VCD/FST do not: the 9-value std_logic system
-- (incl. 'Z'/'L'/'H'), enumerations, integer/natural, unsigned, arrays, and
-- records. GHDL dumps all of these to GHW via --wave.
--
-- Regenerate the fixture with tool/ghw_fixtures/regen.sh (needs GHDL).
-- This source is in-house (CC0) — see the fixture's .provenance.json.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity wavecrux_vhdl_types_tb is
end entity;

architecture sim of wavecrux_vhdl_types_tb is
  type state_t is (IDLE, LOAD, RUN, DONE);
  type byte_array_t is array (0 to 3) of std_logic_vector(7 downto 0);
  type pixel_t is record
    r : std_logic_vector(3 downto 0);
    g : std_logic_vector(3 downto 0);
    b : std_logic_vector(3 downto 0);
  end record;

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal tri   : std_logic := 'Z';   -- high-impedance
  signal weak  : std_logic := 'L';   -- weak pull-down
  signal bus8  : std_logic_vector(7 downto 0) := (others => '0');
  signal cnt   : unsigned(7 downto 0) := (others => '0');
  signal num   : integer range 0 to 255 := 0;
  signal state : state_t := IDLE;
  signal mem   : byte_array_t := (others => (others => '0'));
  signal pix   : pixel_t := (r => (others => '0'),
                             g => (others => '0'),
                             b => (others => '0'));
begin
  -- 100 MHz clock.
  clk <= not clk after 5 ns;

  -- Synchronous datapath.
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cnt   <= (others => '0');
        num   <= 0;
        state <= IDLE;
      else
        cnt  <= cnt + 1;
        num  <= (num + 1) mod 256;
        bus8 <= std_logic_vector(cnt);
        case state is
          when IDLE => state <= LOAD;
          when LOAD => state <= RUN;
          when RUN  => state <= DONE;
          when DONE => state <= IDLE;
        end case;
        mem(0)  <= std_logic_vector(cnt);
        mem(1)  <= std_logic_vector(cnt + 1);
        pix.r   <= std_logic_vector(cnt(3 downto 0));
        pix.g   <= std_logic_vector(cnt(7 downto 4));
      end if;
    end if;
  end process;

  -- Release reset and toggle the tri-state / weak lines once, then idle.
  process
  begin
    wait for 23 ns;
    rst  <= '0';
    tri  <= '1';
    weak <= 'H';
    wait for 200 ns;
    tri  <= 'Z';
    wait;
  end process;
end architecture;
