-- Clean-room sample VHDL design for RTL stems generation tests.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter is
  port (
    clk   : in  std_logic;
    rst_n : in  std_logic;
    q     : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of counter is
  signal cnt : unsigned(7 downto 0);
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if rst_n = '0' then
        cnt <= (others => '0');
      else
        cnt <= cnt + 1;
      end if;
    end if;
  end process;

  q <= std_logic_vector(cnt);
end architecture;
