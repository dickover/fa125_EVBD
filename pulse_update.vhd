-- pulse update - 11/23/10    EJ ;

-- on receipt of 'go_pulse', generate pulse 'pulse_out' of width 'pulse_width' + 1 'clk' periods
-- 'go_pulse' is assumed synchronous to 'clk'
-- 'pulse_out' is updated to width of 'go_pulse' if programmed width is less
-- 'pulse_out' is updated by 'go_pulse' assertion  

library ieee;
use ieee.std_logic_1164.all;

entity pulse_update is
	generic( bitlength: integer );
	port( 	  go_pulse: in std_logic;									-- go_pulse is assumed synchronized to clk
		   pulse_width: in std_logic_vector((bitlength - 1) downto 0);	-- pulse width - 1 in clk periods
				   clk: in std_logic;
			     reset: in std_logic;
			 pulse_out: out std_logic );								-- assert pulse for width + 1 clock periods (or update)
end pulse_update;

architecture a1 of pulse_update is

	component counter_udsl is
		generic( bitlength: integer );
		port(       updown: in std_logic;
		         count_ena: in std_logic;
				     sload: in std_logic;
				      data: in std_logic_vector((bitlength - 1) downto 0);
				       clk: in std_logic;
				     reset: in std_logic;
			    zero_count: out std_logic
--			     max_count: out std_logic;
--			       counter: out std_logic_vector((bitlength - 1) downto 0)
			);
	end component;
														
	constant s0: std_logic_vector(1 downto 0)  := "00";
	constant s1: std_logic_vector(1 downto 0)  := "11";
	constant s2: std_logic_vector(1 downto 0)  := "01";

	signal ps,ns: std_logic_vector(1 downto 0);
	
	signal zero_count: std_logic;
	signal load: std_logic;
	
begin

p1:	process (reset,clk)
	begin
		if reset = '1' then 
			ps <= s0;
		elsif rising_edge(clk) then 
			ps <= ns;
		end if;
	end process p1;
	
p2:	process (ps, go_pulse, zero_count)
	begin
		case ps is
			when s0  =>	
				if ( go_pulse = '1' ) then
					ns <= s1 ;
				else 
					ns <= s0 ;
				end if;
				
			when s1  =>
				if ( (go_pulse = '1') ) then
					ns <= s2 ;
				elsif ( (zero_count = '1') and (go_pulse = '0') ) then
					ns <= s0 ;
				else 
					ns <= s1 ;
				end if;
				
			when s2  =>
					ns <= s1 ;
				
			when others =>			
					ns <= s0;
		end case;
	end process p2;
				
	pulse_out <= ps(0);
	load 	  <= not ps(1);
	
x1:	counter_udsl generic map ( bitlength => bitlength )
			     port map (    
								updown => '0',				-- count down
								count_ena => '1',				-- always enabled
							   sload => load,				-- load
								data => pulse_width,		
								clk => clk,
							   reset => reset,
								zero_count => zero_count
--								max_count => open,
--								counter => open 
							  );
	
end a1;
	