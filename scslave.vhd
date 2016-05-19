-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- + Indiana University CEEM    /    GlueX/Hall-D Jefferson Lab                    +
-- + 72 channel 12/14 bit 125 MSPS ADC module with digital signal processing       +
-- + Serial interface slave (for slow controls in proc & fe FPGA's)                +
-- + Gerard Visser - gvisser@indiana.edu - 812 855 7880                            +
-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- $Id: scslave.vhd 25 2012-04-20 18:35:34Z gvisser $

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library unisim;
use unisim.vcomponents.all;
library work;
use work.miscellaneous.all;

entity scslave is
   port (
      -- local clock (for internal use in 'timeout' protocol)
      osc: in std_logic;
      -- serial interface
      sclk,sin: in std_logic;
      sout: out std_logic;
      -- local interface (all synchronous to interface clock sclk (non-continuous!))
      ca: out std_logic_vector(13 downto 0);
      cwr: out std_logic;
      cwd: out std_logic_vector(31 downto 0);
      crd: in std_logic_vector(31 downto 0);
      crdv,cwack: in std_logic;
      crack: out std_logic);
end entity scslave;

architecture scslave_0 of scslave is
   signal timer: integer range 0 to 7;
   signal sclk_r,sclk_r2,timeout,clr_timeout,timeout_r,timeout_r2: std_logic;
   signal rreg: std_logic_vector(45 downto 0);
   type scsl_type is (idle,rd,wr);
   signal scsl: scsl_type;
   signal k: integer range 0 to 31;
   signal wreg: std_logic_vector(32 downto 0);

begin

   process(osc)
   begin
      if osc'event and osc='1' then
         sclk_r <= sclk; sclk_r2 <= sclk_r;  -- resync for safe usage
         if sclk_r2='0' then
            -- Timeout value here should be long enough never to trip on sclk bit high time, but short
            -- enough that there is little/no risk of timeout being asserted epsilon before next sck rising
            -- edge.
            timer <= 5;
         elsif timer/=0 then
            timer <= timer-1;
         end if;
      end if;
   end process;
   process(osc,clr_timeout)
   begin
      if clr_timeout='1' then
         timeout <= '0';
      elsif osc'event and osc='1' then
         if timer=1 then
            timeout <= '1';
         end if;
      end if;
   end process;
   process(sclk)
   begin
      if sclk'event and sclk='1' then
         timeout_r <= timeout;       -- resync for safe usage
         timeout_r2 <= timeout_r;    -- for edge detection
         if timeout_r='1' and timeout_r2='0' then
            rreg(45 downto 2) <= (others => '1');
            rreg(1 downto 0) <= rreg(0)&sin;
            clr_timeout <= '1';
         else
            rreg <= rreg(44 downto 0)&sin;
            clr_timeout <= '0';
         end if;
         case scsl is
            when idle =>             -- find start of frame; note last clock cycle of frame also taken here
               wreg <= (others => '1');
               if rreg(16 downto 15)="00" then
                  k <= 31;
                  if rreg(14)='0' then
                     if crdv='1' then
                        wreg <= crd&'0';
                     end if;
                     scsl <= rd;
                  else
                     scsl <= wr;
                  end if;
               end if;
            when rd =>               -- shift out the read data & ack bit
               wreg <= wreg(31 downto 0)&'1';
               k <= k-1;
               if k=0 then
                  rreg <= (others => '1');  -- IMPORTANT to clear this now lest we make a spurious cycle!
                  scsl <= idle;
               end if;
            when wr =>               -- shift in the write data and maybe set ack bit
               k <= k-1;
               if k=0 then
                  if cwack='1' then
                     wreg(32) <= '0';
                  end if;
                  scsl <= idle;
                  rreg <= (others => '1');  -- IMPORTANT to clear this now lest we make a spurious cycle!
               end if;
         end case;
      end if;
   end process;
   ca <= rreg(45 downto 32) when scsl=wr else rreg(13 downto 0);
   cwr <= bool2std(scsl=wr and k=0);
   cwd <= rreg(31 downto 0);
   crack <= bool2std(scsl=idle and rreg(16 downto 14)="000" and crdv='1');
   sout <= wreg(32);

-- THERE IS still a bit of a risk lurking here... If a sclk pulse is missed, or any other reason we might be left
-- driving sout low, then this will mess up the other frontend slave's (giving bad read data and false acknowledge).
-- THE TIMEOUT should IMMEDIATELY (regardless of sclk) force sout high. This may need some thinking, how to
-- accomplish that??
   
end architecture scslave_0;
