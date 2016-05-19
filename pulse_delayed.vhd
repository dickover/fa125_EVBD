-- pulse delayed  -  10/4/12 VHDL    EJ ;

-- on receipt of 'go_pulse', generate pulse of pulse width 'pulse_width' + 1 'clk' periods
-- delayed by 'delay_width' + 1 'clk' periods
-- 'go_pulse' is assumed synchronous to 'clk' 

library ieee;
use ieee.std_logic_1164.all;

entity pulse_delayed is
	generic( bitlength: integer );
	port( 	  go_pulse: in std_logic;									-- go_pulse is assumed synchronized to clk
		   delay_width: in std_logic_vector((bitlength - 1) downto 0);	-- delay width - 1 in clk periods
		   pulse_width: in std_logic_vector((bitlength - 1) downto 0);	-- pulse width - 1 in clk periods
				   clk: in std_logic;
			     reset: in std_logic;
--			 delay_out: out std_logic;									-- pulse asserted for delay period
			 pulse_out: out std_logic );								-- delayed pulse out
end pulse_delayed;

architecture a1 of pulse_delayed is

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

--												   -++														
	constant s0: std_logic_vector(2 downto 0)  := "000";
	constant s1: std_logic_vector(2 downto 0)  := "001";
	constant s2: std_logic_vector(2 downto 0)  := "010";
	constant s3: std_logic_vector(2 downto 0)  := "100";
--												   -++														

	signal ps,ns: std_logic_vector(2 downto 0);
	
	signal zero_count_1, zero_count_2: std_logic;
	signal pulse_out_n, delay_out_n: std_logic;
	signal delay_out: std_logic;
	
begin

p1:	process (reset,clk)
	begin
		if reset = '1' then 
			ps <= s0;
		elsif rising_edge(clk) then 
			ps <= ns;
		end if;
	end process p1;
	
p2:	process (ps, go_pulse, zero_count_1, zero_count_2)
	begin
		case ps is
			when s0  =>	
				if ( go_pulse = '1' ) then
					ns <= s1 ;
				else 
					ns <= s0 ;
				end if;
				
			when s1  =>
				if ( zero_count_1 = '1' ) then
					ns <= s2 ;
				else 
					ns <= s1 ;
				end if;
				
			when s2  =>
				if ( zero_count_2 = '1' ) then
					ns <= s3 ;
				else 
					ns <= s2 ;
				end if;
				
			when s3  =>
				if ( go_pulse = '0' ) then
					ns <= s0 ;
				else 
					ns <= s3 ;
				end if;
				
			when others =>			
					ns <= s0;
		end case;
	end process p2;
				
	delay_out <= ps(0);
	delay_out_n <= not ps(0);
	
	pulse_out <= ps(1);
	pulse_out_n <= not ps(1);
	
x1:	counter_udsl generic map ( bitlength => bitlength )
			     port map (    updown => '0',				-- count down
						    count_ena => '1',				-- always enabled
							    sload => delay_out_n,		-- load when pulse not asserted
								 data => delay_width,		-- (i.e. count when pulse asserted)
								  clk => clk,
							    reset => reset,
						   zero_count => zero_count_1
--						    max_count => open,
--							  counter => open 
							  );
	
x2:	counter_udsl generic map ( bitlength => bitlength )
			     port map (    updown => '0',				-- count down
						    count_ena => '1',				-- always enabled
							    sload => pulse_out_n,		-- load when pulse not asserted
								 data => pulse_width,		-- (i.e. count when pulse asserted)
								  clk => clk,
							    reset => reset,
						   zero_count => zero_count_2
--						    max_count => open,
--							  counter => open 
							  );
	
end a1;
	