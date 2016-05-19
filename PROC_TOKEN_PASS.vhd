--  C:\USERS\DICKOVER\DOCUMENTS\...\PROC_TOKEN_PASS.vhd
--  VHDL code created by Xilinx's StateCAD 10.1
--  Fri Oct 09 15:35:35 2015

--  This VHDL code (for use with Xilinx XST) was generated using: 
--  enumerated state assignment with structured code format.
--  Minimization is enabled,  implied else is enabled, 
--  and outputs are area optimized.

LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY PROC_TOKEN_PASS IS
	PORT (CLK,EvbTokIn,FeRdBusy_n,RESET_N,TRIG_GO: IN std_logic;
		DEC_TRIG_CNT,EvbTokOut,FeRdCmd : OUT std_logic);
END;

ARCHITECTURE BEHAVIOR OF PROC_TOKEN_PASS IS
	TYPE type_sreg IS (Both_Tokens_back,Busy_Return,STATE0,STATE1,STATE2,TRIG);
	SIGNAL sreg, next_sreg : type_sreg := STATE0;
BEGIN
	PROCESS (CLK, next_sreg)
	BEGIN
		IF CLK='1' AND CLK'event THEN
			sreg <= next_sreg;
		END IF;
	END PROCESS;

	PROCESS (sreg,EvbTokIn,FeRdBusy_n,RESET_N,TRIG_GO)
	BEGIN
		DEC_TRIG_CNT <= '0'; EvbTokOut <= '0'; FeRdCmd <= '0'; 

		next_sreg<=STATE0;

		IF ( RESET_N='0' ) THEN
			next_sreg<=STATE0;
			FeRdCmd<='0';
			EvbTokOut<='0';
			DEC_TRIG_CNT<='0';
		ELSE
			CASE sreg IS
				WHEN Both_Tokens_back =>
					FeRdCmd<='0';
					EvbTokOut<='0';
					DEC_TRIG_CNT<='1';
					next_sreg<=STATE2;
				WHEN Busy_Return =>
					DEC_TRIG_CNT<='0';
					FeRdCmd<='1';
					EvbTokOut<='1';
					IF ( FeRdBusy_n='0' ) THEN
						next_sreg<=STATE1;
					 ELSE
						next_sreg<=Busy_Return;
					END IF;
				WHEN STATE0 =>
					FeRdCmd<='0';
					EvbTokOut<='0';
					DEC_TRIG_CNT<='0';
					IF ( TRIG_GO='1' ) THEN
						next_sreg<=TRIG;
					 ELSE
						next_sreg<=STATE0;
					END IF;
				WHEN STATE1 =>
					FeRdCmd<='0';
					DEC_TRIG_CNT<='0';
					EvbTokOut<='1';
					IF ( FeRdBusy_n='1' ) THEN
						next_sreg<=Busy_Return;
					ELSIF ( EvbTokIn='1' ) THEN
						next_sreg<=Both_Tokens_back;
					 ELSE
						next_sreg<=STATE1;
					END IF;
				WHEN STATE2 =>
					FeRdCmd<='0';
					EvbTokOut<='0';
					DEC_TRIG_CNT<='0';
					next_sreg<=STATE0;
				WHEN TRIG =>
					FeRdCmd<='0';
					DEC_TRIG_CNT<='0';
					EvbTokOut<='1';
					IF ( FeRdBusy_n='1' ) THEN
						next_sreg<=Busy_Return;
					 ELSE
						next_sreg<=TRIG;
					END IF;
				WHEN OTHERS =>
			END CASE;
		END IF;
	END PROCESS;
END BEHAVIOR;
