-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- + Indiana University CEEM    /    GlueX/Hall-D Jefferson Lab                    +
-- + 72 channel 12/14 bit 125 MSPS ADC module with digital signal processing       +
-- + Processor FPGA (Trigger handling, readout from FE FPGA, processing)           +
-- + Gerard Visser - gvisser@indiana.edu - 812 855 7880                            +
-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- $Id: processor.vhd 26 2012-04-24 03:31:47Z gvisser $

-- ver 0x10101 Raw mode
-- ver 0x10201 250 processing modes
-- ver 0x10202 250 processing modes, ch mask, pulser, playback, serial line bug fix
-- ver 0x10203 event cnt bug fix
-- ver 0x10205 avg 16 samples on fe tdc_SM
-- ver 0x10206 bug fix constraints on fe, proc
-- ver 0x10207 bug fix buffer overload on main
-- ver 0x10208 kicked out headers and trailers on proc
-- ver 0x10209 increased buffers on Proc to 32768  
-- ver 0x20001 New Alogorithms on FE, everything clocked at 125, daisy chain using 16 bits for data with the 
-- write enable passed on bit 16, 
-- ver 0x20006 Busy, fixes on FE
-- ver 0x20007-d removed chipscope, chenges on fe
-- ver 0x2000F -- trignumber for busy does not block if = 0. Added high water trig level that blocks triggers.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
library unisim;
use unisim.vcomponents.all;
library work;
use work.miscellaneous.all;	  

use IEEE.std_logic_unsigned.all; 
use IEEE.std_logic_arith.all;
  

entity processor is
  -- generic(svnver: integer);
   port (
      -- clock & trigger & related things
      aclk_p,aclk_n: in std_logic;
      p0_trg_p,p0_trg_n,p2_trg_p,p2_trg_n: in std_logic_vector(2 downto 0); --P0trig(1) = SYNC
      p0_busy: out std_logic;
		--p2_busy: out std_logic;
      muloth: in std_logic;             -- local multiplicity trigger
      aFeWrCmd,bFeWrCmd: out std_logic;
      pulser_n: out std_logic;
      led_trig_n,led_busy_n: out std_logic;
      -- slow controls
      sclk,sin: in std_logic;
		--softRst: in std_logic;
      sout: out std_logic;
      sbao: out std_logic;              -- to SD (VXS)
      --sbai: in std_logic;
		--sbbi: in std_logic;          -- from SD (VXS)
      -- readout and data processing
      osc : in std_logic;
--		rclk,wclk: in std_logic;
      arclko,brclko,fwclko : out std_logic;
--		rclko,wclko,
		p2v_fwclko: out std_logic;
      aFeRdCmd,aFeRdStart: out std_logic;
--     aAF_n : in std_logic;
		aFeRdBusy_n : in std_logic;
		aFeRdErr_n: in std_logic;
	   aEvbHold,aEvbTokOut: out std_logic;
      aEvbTokIn: in std_logic;
      aEvbD: in std_logic_vector(16 downto 0);
      bFeRdCmd,bFeRdStart: out std_logic;
--      bAF_n : in std_logic;
		bFeRdBusy_n : in std_logic;
		bFeRdErr_n : in std_logic;
	   bEvbHold,bEvbTokOut: out std_logic;
      bEvbTokIn: in std_logic;
      bEvbD: in std_logic_vector(16 downto 0);
--      p2v_fWen_n: out std_logic;
--      p2v_fD: out std_logic_vector(17 downto 16);
      p2v_spare0: in std_logic;
		p2v_spare1: out std_logic;
      --fFull_n: in std_logic;
      fLoad_n,fWen_n: out std_logic;
      fDout: out std_logic_vector(17 downto 0);
      fMRst_n: out std_logic
      );
	attribute period: string;
   attribute period of osc: signal is "12.5ns";
end processor;

architecture processor_0 of processor is

	--signal aclk_i,aclk_i2,
	signal aclk: std_logic;
	--signal trg_i,tt: std_logic_vector(p2_trg_p'range);  -- only OLD??
	--signal test0,test0r: std_logic_vector(p2_trg_p'range);
	--signal test1,test2,test3,test4: std_logic;
	--constant YMAX: integer := 125000000/11;  -- 11 Hz
	--signal y: integer range 0 to YMAX;
	--signal z: integer range 0 to 7;
	signal ca: std_logic_vector(13 downto 0);
	signal crdv,cwr,cwack: std_logic;
	signal crd,cwd: std_logic_vector(31 downto 0);
	signal csr: std_logic_vector(31 downto 0):=x"00000000"; --TB stuff, remember!!!!
	signal led_busy,led_trig: std_logic := '0';
	
	signal feWrCmd_pre: std_logic; 
	signal feWrCmd_pre_D, feWrCmd_pre_Q: std_logic := '0';
	
	signal p2_trg_i: std_logic_vector(p2_trg_p'range);
	signal p0_trg_i: std_logic_vector(p0_trg_p'range);
	signal ext_trg,ext_trg_r,ext_trg_r2: std_logic;
	signal p0_ext_trg,p0_ext_trg_r,p0_ext_trg_r2: std_logic;
	signal int_trg_r,int_trg_r2,int_trg_r3: std_logic;
	signal SW_trig_r,SW_trig_r2,SW_trig_r3: std_logic;
	
	--signal SYNC_reset: std_logic:='1';
	signal p0_SYNC,p0_SYNC_r,p0_SYNC_r2: std_logic;
	
	signal trig2_go: std_logic:='1';
	signal p0_trig2,p0_trig2_r,p0_trig2_r2: std_logic;	
---------------------------------------------------------------------
---------------------------------------------------------------------
--signal fcontrol: std_logic_vector(31 downto 0);
	signal fcontrol: std_logic;

	signal trig_source: std_logic_vector(1 downto 0):="00";
	--signal dummy_data, adc_read: std_logic_vector(15 downto 0);
	--signal fifo_go, dummy_rst,fe_rd,Evb_sel,spare0: std_logic;
	signal fLoad: std_logic; 
---------------------------------------------------------------------
---------------------------------------------------------------------
	signal RESET_N			: std_logic;  	
	signal BLOCK_SIZE		: std_logic_vector(21 downto 0) := "0000000000000000000001"; -- sw register default is 1
	--signal fe_data_out		: std_logic_vector(17 downto 0); 
	
	signal fe_data_out_D,fe_data_out_Q		: std_logic_vector(15 downto 0);
	signal fe_data_out_2D,fe_data_out_2Q	: std_logic_vector(15 downto 0);
	
	signal fWen_n_D, fWen_n_Q		 : std_logic := '1';
	signal fWen_n_Q_b, fWen_n_2Q_b : std_logic := '1';
	signal fWen_n_2D, fWen_n_2Q 	 : std_logic := '1';
	signal fWen_n_3D, fWen_n_3Q 	 : std_logic := '1';
	signal fWen_n_3Q_b				: std_logic := '1';

	signal aEvbD_D,aEvbD_Q		: std_logic_vector(16 downto 0);
	signal aEvbD_2_D,aEvbD_2_Q	: std_logic_vector(16 downto 0); -- for testing
	signal bEvbD_D,bEvbD_Q		: std_logic_vector(16 downto 0);
	signal bEvbD_2_D,bEvbD_2_Q	: std_logic_vector(16 downto 0);
	
--	signal afe_data_out		: std_logic_vector(17 downto 0);
--	signal bfe_data_out		: std_logic_vector(17 downto 0);
--	signal data_insert		: std_logic_vector(17 downto 0);

---------------------------------------------------------------------
--------------------------------------------------------------------- 
	signal OK_trig			: std_logic;
	signal TRIG_GO			: std_logic;
	signal bTRIG_GO			: std_logic;

	signal DEC_TRIG_CNT		: std_logic;
	signal bDEC_TRIG_CNT	: std_logic;
	
	signal INC_TRIG_CNT		: std_logic;
	signal PINC_TRIG_CNT 	: std_logic;
	signal INC_TRIG_CNT_D 	: std_logic; ---- increment PTW_DATA_BLOCK_CNT_Q when 1; 
	signal INC_TRIG_CNT_Q 	: std_logic;
	signal PINC_TRIG_CNT_D,PINC_TRIG_CNT_2D : std_logic;	
	signal PINC_TRIG_CNT_Q,PINC_TRIG_CNT_2Q : std_logic;
	
	signal INC_TRIG2_CNT		: std_logic;
	signal PINC_TRIG2_CNT 	: std_logic;
	signal INC_TRIG2_CNT_D 	: std_logic; ---- increment PTW_DATA_BLOCK_CNT_Q when 1; 
	signal INC_TRIG2_CNT_Q 	: std_logic;
	signal PINC_TRIG2_CNT_D,PINC_TRIG2_CNT_2D : std_logic;	
	signal PINC_TRIG2_CNT_Q,PINC_TRIG2_CNT_2Q : std_logic;
	signal OK_trig2	: std_logic;
	
	signal aFeWrCmd_D,aFeWrCmd_Q	: std_logic;
	signal bFeWrCmd_D,bFeWrCmd_Q	: std_logic;
 
	signal TRIG_CNT_D 		: std_logic_vector(7 downto 0);  --Number of PTW data blocks ready for process
	signal TRIG_CNT_Q 		: std_logic_vector(7 downto 0);  --Number of PTW data blocks ready for process
	signal bTRIG_CNT_D 		: std_logic_vector(7 downto 0);  --Number of PTW data blocks ready for process
	signal bTRIG_CNT_Q 		: std_logic_vector(7 downto 0);  --Number of PTW data blocks ready for process 
	signal Event_TRIG_CNT_D	: std_logic_vector(7 downto 0);
	signal Event_TRIG_CNT_Q	: std_logic_vector(7 downto 0);
	
	signal TRIG_CNT_STATUS_D 		: std_logic_vector(31 downto 0);  
	signal TRIG_CNT_STATUS_Q 		: std_logic_vector(31 downto 0);
		
	signal PDEC_TRIG_CNT 	: std_logic;
	signal bPDEC_TRIG_CNT 	: std_logic;
	signal DEC_Evt_Trig_cnt : std_logic;
	
	signal DEC_TRIG_BUF1_D 		: std_logic; --- Double buffer in case Processing Block run at different clock
	signal DEC_TRIG_BUF1_Q 		: std_logic;
	signal DEC_TRIG_BUF2_D 		: std_logic;
	signal DEC_TRIG_BUF2_Q 		: std_logic;
	signal bDEC_TRIG_BUF1_D 	: std_logic; --- Double buffer in case Processing Block run at different clock
	signal bDEC_TRIG_BUF1_Q 	: std_logic;
	signal bDEC_TRIG_BUF2_D 	: std_logic;
	signal bDEC_TRIG_BUF2_Q 	: std_logic; 
	signal DEC_Evt_TRIG_BUF1_D	: std_logic;
	signal DEC_Evt_TRIG_BUF1_Q	: std_logic;
	signal DEC_Evt_TRIG_BUF2_D	: std_logic;
	signal DEC_Evt_TRIG_BUF2_Q	: std_logic;
	
	signal aevbd_rd_en,bevbd_rd_en					: std_logic;
	signal aevbd_rd_en_D,aevbd_rd_en_Q				: std_logic;
	signal bevbd_rd_en_D,bevbd_rd_en_Q				: std_logic;
	
--	signal aAF_n_D,aAF_n_Q								: std_logic;
--	signal bAF_n_D,bAF_n_Q								: std_logic;
	signal adaisy_wr_en,bdaisy_wr_en					: std_logic;
	
	signal aFeRdBusy_n_D,aFeRdBusy_n_Q,aFeRdBusy_n_T 				: std_logic;
	signal aFeRdCmd_D,aFeRdCmd_Q,aFeRdCmd_T		: std_logic;
	signal bFeRdBusy_n_D,bFeRdBusy_n_Q,bFeRdBusy_n_T				: std_logic;
	signal bFeRdCmd_D,bFeRdCmd_Q,bFeRdCmd_T		: std_logic;
	
	signal aEvbTokIn_D,aEvbTokIn_Q					: std_logic;
	signal bEvbTokIn_D,bEvbTokIn_Q					: std_logic;
	
	signal aEvbTokOut_D,aEvbTokOut_Q,aEvbTokOut_Q_B,aEvbTokOut_T : std_logic;
	signal bEvbTokOut_D,bEvbTokOut_Q,bEvbTokOut_Q_B,bEvbTokOut_T : std_logic;
	
	signal daisy_clk						: std_logic;
	signal osc_b, aFeRdErr_n_Q, bFeRdErr_n_Q							: std_logic;
	
	signal aFD,bFD							: std_logic_vector(15 downto 0);  
	signal afD_D, bfD_D					: std_logic_vector(15 downto 0);
	signal afD_Q, bfD_Q					: std_logic_vector(15 downto 0);
	
	signal aempty_D,bempty_D					: std_logic; 
	signal aempty_Q,bempty_Q					: std_logic;
	--signal aempty,bempty				: std_logic;
	signal chip_ev_cnt_D,chip_ev_cnt_Q		: std_logic_vector(3 downto 0);
	signal INC_chip_ev,Clear_chip_ev		: std_logic;
	signal A_SEL,B_SEL						: std_logic;
	signal A_Trailer,B_Trailer				: std_logic; 
	signal A_Trailer_WR,B_Trailer_WR				: std_logic;
	
	signal Block_Done						: std_logic;
	signal Event_Trig_Go					: std_logic;
	signal INC_Event_cnt					: std_logic;
	signal DEC_Event_cnt					: std_logic;
	signal pINC_Event_cnt					: std_logic;
	signal PDEC_Evt_TRIG_CNT				: std_logic;
	signal INC_chip_ev1_D,INC_chip_ev1_Q	: std_logic;
	signal INC_chip_ev2_D,INC_chip_ev2_Q	: std_logic;
	signal pINC_chip_ev						: std_logic;
	signal Clear_Event						: std_logic;
	signal Event_cnt_D,Event_cnt_Q			: std_logic_vector(21 downto 0); -- 2 for now for testing 
	signal Event_Done						: std_logic;

	signal A_GO,B_GO						: std_logic; 
	signal Block_Header_GO1					: std_logic;
	signal Block_Header_GO2					: std_logic;
	signal Filler_Word_GO					: std_logic;
	signal Block_Trail_GO1					: std_logic;
	signal Block_Trail_GO2					: std_logic;
	
	signal Block_Trail_GO2_D, Block_Trail_GO2_Q : std_logic;
	
	signal Filler_Word_GO1					: std_logic;
	signal Filler_Word_GO2					: std_logic;
	--signal Block_Thresh					: std_logic_vector(7 downto 0); -- need bigger number, from sw 
	signal EVEN									: std_logic;
	signal FWEN									: std_logic;
	signal slot_id								: std_logic_vector(4 downto 0);
	signal data_format							: std_logic_vector(2 downto 0);
	signal INC_blk_number  						: std_logic;
	signal block_number							: std_logic_vector(6 downto 0) := "0000001";
	signal block_number_D,block_number_Q		: std_logic_vector(6 downto 0) := "0000001";
	signal number_of_Events						: std_logic_vector(7 downto 0);
	signal BLOCK_HEADER							: std_logic_vector(35 downto 0);
	signal BLOCK_TRAILER						: std_logic_vector(35 downto 0);
	signal Filler_Word   						: std_logic_vector(35 downto 0);
	signal EVEN_ODD_cnt_D,EVEN_ODD_cnt_Q		: std_logic_vector(3 downto 0);
	
	signal INC_Blk_Evt_Cnt						: std_logic;
	signal INC_Blk_Evt_Cnt_D,INC_Blk_Evt_Cnt_Q	: std_logic; 
	signal INC_Blk_Evt_Cnt_2D,INC_Blk_Evt_Cnt_2Q	: std_logic;
	signal p2v_spare1_D,p2v_spare1_Q : std_logic;
	
	signal word_cnt						: std_logic;
	signal word_count 					: std_logic_vector(21 downto 0);
	signal word_count_D, word_count_Q: std_logic_vector(21 downto 0);
	signal SW_trig							: std_logic;
	-- new regs
	signal CTRL2							: std_logic_vector(1 downto 0);
	signal trig_enable,sync_enable 	: std_logic := '1';
	signal trig_cnt_rst					: std_logic := '1';
	signal p_trig_cnt_rst				: std_logic;
	signal clk_cnt_rst,	p_clk_cnt_rst				: std_logic;
	
	signal clk_count_D, clk_count_Q	: std_logic_vector(31 downto 0);
	
	signal sync_cnt_rst					: std_logic := '1';
	signal p_sync_cnt_rst				: std_logic;
	signal SYNC_CNT_STATUS_D,SYNC_CNT_STATUS_Q			: std_logic_vector(31 downto 0);
	
	signal trig2_cnt_rst					: std_logic := '1';
	signal p_trig2_cnt_rst				: std_logic;
	signal TRIG2_CNT_STATUS_D,TRIG2_CNT_STATUS_Q			: std_logic_vector(31 downto 0);
	
	signal go_pulse, pulser_out, hw_trig							: std_logic;
	signal go_pulse_trig, pulser_trig, pulser_trig_delay 		: std_logic;
	
	signal pulser_trig_delay_width						: std_logic_vector(11 downto 0);
	signal pulser_ctrl, pulser_delay_trig	: std_logic_vector(1 downto 0);
	signal pulser_mode 					: std_logic;
	
	signal go_pulse_trig_A,go_pulse_trig_B 						: std_logic;
	signal go_pulse_trig_D,go_pulse_trig_Q, go_pulse_trig_P  : std_logic;
	signal go_pulse_trig_2D,go_pulse_trig_2Q						: std_logic;
		
	component pulse_update is
		generic( bitlength: integer );
		port( 	  
				go_pulse			: in std_logic;						-- go_pulse is assumed synchronized to clk
				pulse_width		: in std_logic_vector((bitlength - 1) downto 0);	-- pulse width - 1 in clk periods
				clk				: in std_logic;
				reset				: in std_logic;
				pulse_out		: out std_logic );					-- assert pulse for width + 1 clock periods
	end component;
	
	component pulse_delayed is
		generic( bitlength: integer );
		port( 	  go_pulse: in std_logic;									-- go_pulse is assumed synchronized to clk
			   delay_width: in std_logic_vector((bitlength - 1) downto 0);	-- delay width - 1 in clk periods
		       pulse_width: in std_logic_vector((bitlength - 1) downto 0);	-- pulse width - 1 in clk periods
				       clk: in std_logic;
			         reset: in std_logic;
--			     delay_out: out std_logic;									-- pulse asserted for delay period
			     pulse_out: out std_logic );								-- delayed pulse out
	end component;
		
---------------------------------------------------------------------
--------------------------------------------------------------------- 

	component PROC_TOKEN_PASS 
	   PORT (
		   CLK			: IN std_logic;
		   EvbTokIn		: IN std_logic;
		   RESET_N		: IN std_logic;
		   TRIG_GO		: IN std_logic;	
		   FeRdBusy_n	: IN std_logic;
		   EvbTokOut	: OUT std_logic;
		   FeRdCmd		: OUT std_logic;
		   DEC_TRIG_CNT	: OUT std_logic);
	END component;
	
	COMPONENT new_daisy_4096 -- 16384 32768
		PORT (
				 rst : IN STD_LOGIC;
				 wr_clk : IN STD_LOGIC;
				 rd_clk : IN STD_LOGIC;
				 din : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
				 wr_en : IN STD_LOGIC;
				 rd_en : IN STD_LOGIC;
				 dout : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
				 full : OUT STD_LOGIC;
				 empty : OUT STD_LOGIC
			);
	END COMPONENT;
	
	
	signal data_count_A,data_count_B : STD_LOGIC_VECTOR(13 DOWNTO 0);	
	
	component EVBD_MAIN_FIFO 
	 PORT (
	 		CLK 			: IN std_logic;
	 		RESET_N 		: IN std_logic;
	 		A_GO 			: IN std_logic;
			A_Trailer 		: IN std_logic;
			B_GO 			: IN std_logic;
			B_Trailer 		: IN std_logic;
			Block_Done 		: IN std_logic;
			EVEN 			: IN std_logic;
			Event_Done 		: IN std_logic;
			Event_Trig_Go 	: IN std_logic;
			A_SEL 			: OUT std_logic;
			aevbd_rd_en 	: OUT std_logic;
			B_SEL 			: OUT std_logic;
			bevbd_rd_en 	: OUT std_logic;
			Block_Header_Go1 : OUT std_logic;
			Block_Header_Go2 : OUT std_logic;
			Block_Trail_GO1  : OUT std_logic;
			Block_Trail_GO2  : OUT std_logic;
			Clear_chip_ev 	 : OUT std_logic;
			DEC_Evt_Trig_cnt : OUT std_logic;
			Filler_Word_GO1	: OUT std_logic;
			Filler_Word_GO2	: OUT std_logic;
			FWEN_N 			: OUT std_logic;
			word_cnt 			: OUT std_logic;
			--INC_Blk_Evt_Cnt : OUT std_logic;
			--INC_blk_number	: OUT std_logic;
			INC_chip_ev 	: OUT std_logic;
			INC_Event_cnt 	: OUT std_logic
			--DEC_Event_cnt : OUT std_logic
		);
	END component;
	
	signal EVENT_HEAD_Kick, EVENT_TRAIL_Kick : std_logic;
	signal A_Header, B_Header : std_logic;
	signal dontWrite, dontWrite_D, dontWrite_Q : std_logic;
	signal kick_EVEN_ODD_cnt_D, kick_EVEN_ODD_cnt_Q : std_logic_vector(3 downto 0);
	signal kick_EVEN_ODD_cnt_2D, kick_EVEN_ODD_cnt_2Q : std_logic_vector(3 downto 0);
	signal A_Time, B_Time, EVENT_TIME_Kick, dontWriteTime : std_logic;
	signal dontWriteTime_D, dontWriteTime_2D, dontWriteTime_3D : std_logic;
	signal dontWriteTime_Q, dontWriteTime_2Q, dontWriteTime_3Q :std_logic;
	
   component scslave
      port (
         osc         : in  std_logic;
         sclk, sin   : in  std_logic;
         sout        : out std_logic;
         ca          : out std_logic_vector(13 downto 0);
         cwr         : out std_logic;
         cwd         : out std_logic_vector(31 downto 0);
         crd         : in  std_logic_vector(31 downto 0);
         crdv, cwack : in  std_logic;
			crack: out std_logic
			);
   end component;

---------------------------------------------------------------------
---------------------------------------------------------------------
	signal highWaterA, highWaterB : std_logic;
	signal a_wr_clk, b_wr_clk	: std_logic;
	signal trig_limit	: std_logic_vector(7 downto 0) := X"03";
	
	signal RESET_N_D, RESET_N_Q, RESET_N_2D, RESET_N_2Q,RESET_N_3D, RESET_N_3Q: std_logic := '1';
	signal RESET : std_logic;
	signal aFeRdStart_D,aFeRdStart_Q : std_logic :='1';
	signal bFeRdStart_D,bFeRdStart_Q : std_logic :='1';	
	
	signal SYNC_reset: std_logic :='1';
	signal SYNC_reset_D,SYNC_reset_Q : std_logic :='1';
	signal SYNC_reset_2D,SYNC_reset_2Q : std_logic :='1';
	signal SYNC_reset_3D,SYNC_reset_3Q : std_logic :='1';
	
	signal main_reset_D,main_reset_Q : std_logic :='1';
	
	signal max_trig_limit : std_logic_vector(7 downto 0)  := X"04";
	signal HW_trig_limit : std_logic_vector(7 downto 0)  := X"05";
	signal BLOCK_TRIG : std_logic; 
	
begin

	fDout( 17 downto 16) <= "00";
	--p0_busy <= '0'; -- temp fix until actual flag/count from fifo 
	--p0_busy <= '1' when (aFeRdErr_n_Q = '0' or bFeRdErr_n_Q ='0') else '0';
		
	p0_busy <= '1' when ((Event_TRIG_CNT_Q >= max_trig_limit) and max_trig_limit /= X"00") else '0';
   BLOCK_TRIG <= '1' when ((Event_TRIG_CNT_Q >= HW_trig_limit) and HW_trig_limit /= X"00") else '0';	

		
	sbao <= '0'; -- to SD 

   led_busy_n <= '0' when led_busy='1' else '1';
   led_trig_n <= '0' when led_trig='1' else '1';
	
   aclk_IBUFGDS: IBUFGDS 
	generic map (
		DIFF_TERM => TRUE, -- Differential Termination 
		IBUF_LOW_PWR => FALSE, -- Low power (TRUE) vs. performance (FALSE) setting for refernced I/O standards
		IOSTANDARD => "LVDS_25")
   port map(
		I => aclk_p,
		IB => aclk_n,
		O => aclk
	);

	w0: for i in 0 to 2 generate
		w1: IBUFGDS 
		generic map(
			--DIFF_TERM => TRUE, -- Differential Termination 
			IBUF_LOW_PWR => FALSE, -- Low power (TRUE) vs. performance (FALSE) setting for refernced I/O standards
			IOSTANDARD => "LVDS_25")
		port map(
			I => p2_trg_p(i),
			IB => p2_trg_n(i),
			O => p2_trg_i(i)
			);
   end generate;
	
	w2: for i in 0 to 2 generate
      w3: IBUFGDS 
		generic map(
			DIFF_TERM => TRUE, -- Differential Termination 
			IBUF_LOW_PWR => FALSE, -- Low power (TRUE) vs. performance (FALSE) setting for refernced I/O standards
			IOSTANDARD => "LVDS_25")
      port map(
			I => p0_trg_p(i),
			IB => p0_trg_n(i),
			O => p0_trg_i(i)
			);
   end generate;
	
	rBUFG_inst : BUFG
		port map (
			O => osc_B, -- Clock buffer output
			I => osc -- Clock buffer input
			);

---------------------------------------------------------------------------------
----- External clock distribution ----------------------------------------------- 
---------------------------------------------------------------------------------		
	ODDR2_fwclko : ODDR2
		generic map(
			DDR_ALIGNMENT => "NONE", -- Sets output alignment to "NONE", "C0", "C1"
			INIT => '0', -- Sets initial state of the Q output to '0' or '1'
			SRTYPE => "SYNC") -- Specifies "SYNC" or "ASYNC" set/reset
		port map (
			Q => fwclko, -- 1-bit output data
			C0 => aclk, -- 1-bit clock input
			C1 => not aclk, -- 1-bit clock input
			CE => '1', -- 1-bit clock enable input
			D0 => '1', -- 1-bit data input (associated with C0)
			D1 => '0', -- 1-bit data input (associated with C1)
			R => '0', -- 1-bit reset input
			S => '0' -- 1-bit set input
		);		
------
	ODDR2_p2v_fwclko : ODDR2
		generic map(
			DDR_ALIGNMENT => "NONE", -- Sets output alignment to "NONE", "C0", "C1"
			INIT => '0', -- Sets initial state of the Q output to '0' or '1'
			SRTYPE => "SYNC") -- Specifies "SYNC" or "ASYNC" set/reset
		port map (
			Q => p2v_fwclko, -- 1-bit output data
			C0 => aclk, -- 1-bit clock input
			C1 => not aclk, -- 1-bit clock input
			CE => '1', -- 1-bit clock enable input
			D0 => '1', -- 1-bit data input (associated with C0)
			D1 => '0', -- 1-bit data input (associated with C1)
			R => '0', -- 1-bit reset input
			S => '0' -- 1-bit set input
		);		
------      		
	ODDR2_arclko : ODDR2
		generic map(
			DDR_ALIGNMENT => "NONE", -- Sets output alignment to "NONE", "C0", "C1"
			INIT => '0', -- Sets initial state of the Q output to '0' or '1'
			SRTYPE => "SYNC") -- Specifies "SYNC" or "ASYNC" set/reset
		port map (
			Q => arclko, -- 1-bit output data
			C0 => osc_B, -- 1-bit clock input
			C1 => not osc_B, -- 1-bit clock input
			CE => '1', -- 1-bit clock enable input
			D0 => '1', -- 1-bit data input (associated with C0)
			D1 => '0', -- 1-bit data input (associated with C1)
			R => '0', -- 1-bit reset input
			S => '0' -- 1-bit set input
		);	   
------	
	ODDR2_brclko : ODDR2
		generic map(
			DDR_ALIGNMENT => "NONE", -- Sets output alignment to "NONE", "C0", "C1"
			INIT => '0', -- Sets initial state of the Q output to '0' or '1'
			SRTYPE => "SYNC") -- Specifies "SYNC" or "ASYNC" set/reset
		port map (
			Q => brclko, -- 1-bit output data
			C0 => osc_B, -- 1-bit clock input
			C1 => not osc_B, -- 1-bit clock input
			CE => '1', -- 1-bit clock enable input
			D0 => '1', -- 1-bit data input (associated with C0)
			D1 => '0', -- 1-bit data input (associated with C1)
			R => '0', -- 1-bit reset input
			S => '0' -- 1-bit set input
		);
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------

---------------------------------------------------------------------------------
------ Serial Comm between FE/proc/main
---------------------------------------------------------------------------------	
   sc1: scslave
      port map (
	            osc   => osc_B,
	            sclk  => sclk,
	            sin   => sin,
	            sout  => sout,
	            ca    => ca,
	            cwr   => cwr,
	            cwd   => cwd,
	            crd   => crd,
	            crdv  => crdv,
	            cwack => cwack,
					crack => open
			);


	crdv <= '1' when (ca="11010000000000" or ca="11010000000001" or ca="11010000000010" 
						or ca="11010000000100" or ca="11010000000011" or ca="11010000000101"
						or ca="11010000000110" or ca="11010000000111" or ca="11010000001000"
						or ca="11010000001001" or ca="11010000001010" or ca="11010000001011"
						or ca="11010000001100" or ca="11010000001101" or ca="11010000001101"
						or ca="11010000001110") else '0';
						
   with ca select crd <=
						X"0002000F" when "11010000000000", --was &std_logic_vector(to_unsigned(svnver,16)), "aaaa0001" used to identify test FW
						csr when "11010000000001", -- D004
						X"0000000" & "00" & trig_source when "11010000000010", -- D008
						X"0000000" & "000" & fcontrol when "11010000000100", --D010
						X"0000000" & "00" & CTRL2 when "11010000000011", --D00C
						X"00" & "00" & BLOCK_SIZE when "11010000000101", --D014
						TRIG_CNT_STATUS_Q when "11010000000110", --D018 --trig_cnt_rst & "000" & X"00000" & TRIG_CNT_STATUS_Q
						X"00" & "00" & Event_cnt_Q when "11010000000111", --D01C
						clk_count_Q when  "11010000001000", --D020
						SYNC_CNT_STATUS_Q when  "11010000001001", --D024
						trig2_CNT_STATUS_Q when  "11010000001010", --D028
						X"0000000"&"00"& pulser_ctrl(1 downto 0) when  "11010000001011", --D02C
						X"00000"& pulser_trig_delay_width when  "11010000001100", --D030
						X"000000"& trig_limit when  "11010000001101", --D034
						X"0000"& HW_trig_limit & max_trig_limit when  "11010000001110", --D038
						(others => '-') when others;
		
   process(sclk)
   begin
      if sclk'event and sclk='1' then
         if cwr='1' and ca="11010000000001" then
            csr(31 downto 1) <= cwd(31 downto 1);
			elsif cwr='1' and ca="11010000000010" then -- D008 
				trig_source <= cwd(1 downto 0); --
			elsif cwr='1' and ca="11010000000100" then -- D010 	-- temp SW TRIG
				fcontrol <= cwd(4); 
			elsif cwr='1' and ca="11010000000011" then -- D00C -- CTL2, trig en, sync en
				CTRL2 <= cwd(1 downto 0); 
			elsif cwr='1' and ca="11010000000101" then -- D014 -- block size - number of events in block
				BLOCK_SIZE <= cwd(21 downto 0);
			elsif cwr='1' and ca="11010000000110" then -- D018 -- trig count reset
				trig_cnt_rst <= cwd(0); 
			elsif cwr='1' and ca="11010000001000" then -- D020 -- clk count reset
				clk_cnt_rst <= cwd(0);	
			elsif cwr='1' and ca="11010000001001" then -- D024 -- sync count reset
				sync_cnt_rst <= cwd(0); 
			elsif cwr='1' and ca="11010000001010" then -- D028 -- trig2 count reset
				trig2_cnt_rst <= cwd(0);
			elsif cwr='1' and ca="11010000001011" then -- D02C -- pulser_ctrl
				pulser_ctrl <= cwd(1 downto 0);
				--pulser_mode <= cwd(0);
			elsif cwr='1' and ca="11010000001100" then -- D030 -- pulser_trig_delay_width
				pulser_trig_delay_width <= cwd(11 downto 0);
			elsif cwr='1' and ca="11010000001101" then -- D034 -- pulser_trig_delay_width
				trig_limit <= cwd(7 downto 0);
			elsif cwr='1' and ca="11010000001110" then -- D038 -- pulser_trig_delay_width
				max_trig_limit <= cwd(7 downto 0); --max number of trigs before busy
				HW_trig_limit <= cwd(15 downto 8); --max number of trigs brfore trigger rejection
			end if;
      end if;
   end process;
	
	p_trig_cnt_rst  <= trig_cnt_rst  when (cwr='1' and ca="11010000000110") else '0';
	p_clk_cnt_rst   <= clk_cnt_rst   when (cwr='1' and ca="11010000001000") else '0';
	p_sync_cnt_rst  <= sync_cnt_rst  when (cwr='1' and ca="11010000001001") else '0';
	p_trig2_cnt_rst <= trig2_cnt_rst when (cwr='1' and ca="11010000001010") else '0';
	
	cwack <= '1' when (ca="11010000000001" or ca="11010000000010" or ca="11010000000100"
				   or ca="11010000000011" or ca="11010000000101" or ca="11010000000110"
				   or ca="11010000001000" or ca="11010000001001" or ca="11010000001010"
				   or ca="11010000001011" or ca="11010000001100" or ca="11010000001101"
					or ca="11010000001110") else '0';
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------

--	trig_enable <= CTRL2(0); -- not used yet
--	sync_enable <= CTRL2(1); -- not used yet
   
	SW_trig <= '1' when pulser_trig = '1' else '0';

--------------RESET SHENNANIGANS------------------------------------
 

	fMRst_n <= '0' when (RESET_N_Q = '0' or RESET_N_2Q = '0') else '1'; --RESET_N; -- or RESET_N_3Q = '0'
	fLoad <= fcontrol; --00A1 D010, used for main fifo load 
	fLoad_n <= not fLoad; -- logic conversion  			

--	RESET_N <= '0' when (p2v_spare0 = '0' or SYNC_reset = '0') else '1'; -- or SYNC here 
	RESET_N_D <= '0' when (main_reset_Q = '0' or SYNC_reset = '0') else '1'; -- or SYNC here  
	
--	RESET_N <= '0' when RESET_N_2Q = '0' or RESET_N_3Q = '0' else '1'; --change	
--	RESET <= '1' 	when RESET_N_2Q = '0' or RESET_N_3Q = '0' else '0'; --change
	--RESET <= not RESET_N_Q;
	
	RESET_N <= RESET_N_2Q; --change	
	RESET <= not RESET_N_2Q; --change
	
--	aFeRdStart <= RESET_N_Q; -- out to FE, was p2v_spare0
--	bFeRdStart <= RESET_N_Q;
	
	--aFeRdStart <= '0' when (RESET_N_Q = '0' or RESET_N_2Q = '0' or RESET_N_3Q = '0') else '1';-- out to FE, was p2v_spare0
	--bFeRdStart <= '0' when (RESET_N_Q = '0' or RESET_N_2Q = '0' or RESET_N_3Q = '0') else '1';

	--SYNC_reset_D <= '0' when (p0_SYNC_r2='0' and p0_SYNC_r='1') else '1'; --change

	--SYNC_reset <= '0' when (SYNC_reset_Q = '0' or SYNC_reset_2D ='0' or SYNC_reset_2Q ='0') else '1'; --change
	SYNC_reset <= '0' when (SYNC_reset_Q = '0' or SYNC_reset_2Q ='0') else '1'; -- or SYNC_reset_3Q ='0'
	--SYNC_reset <= '0' when (SYNC_reset_Q = '0') else '1';
	
  process(aclk) -- change removed from process
   begin
		if aclk'event and aclk='1' then
			if (p0_SYNC_r2='0' and p0_SYNC_r='1') -- trig on p0_trg(0) rising
			then 
				SYNC_reset_D <= '0';
			else	
				SYNC_reset_D <= '1';
         end if;
      end if;
   end process;
	
	main_reset_D <= p2v_spare0;	
	
---------
	SYNC_CNT_STATUS_D <= SYNC_CNT_STATUS_Q + 1 when SYNC_reset_D = '0' and p_sync_cnt_rst = '0' else
								X"00000000"    		 when p_SYNC_cnt_rst = '1'     else 
								SYNC_CNT_STATUS_Q;  	
	   

	RESET_REG : process (aclk)
	begin
		if (aclk = '1' and aclk'event) then --aclk
			
			main_reset_Q <= main_reset_D;
			
			SYNC_reset_Q <= SYNC_reset_D;
			SYNC_reset_2Q <= SYNC_reset_2D;
			--SYNC_reset_3Q <= SYNC_reset_3D;
			
			RESET_N_Q <= RESET_N_D;
			aFeRdStart <= RESET_N_Q; -- out to FE, was p2v_spare0
			bFeRdStart <= RESET_N_Q;
			
			RESET_N_2Q <= RESET_N_2D;
			--RESET_N_3Q <= RESET_N_3D;

		
		end if;
	end process RESET_REG;
	
	SYNC_reset_2D <= SYNC_reset_Q;
	
	RESET_N_2D <= RESET_N_Q;

	
--	aFeRdStart <= aFeRdStart_Q; -- out to FE, was p2v_spare0
--	bFeRdStart <= bFeRdStart_Q;
-------------- END RESET SHENNANIGANS------------------------------------

---------------------------------------------------------------------------------
--- trig/sync reg
---------------------------------------------------------------------------------
--		aFeWrCmd_D <= feWrCmd_pre_Q; 
--		bFeWrCmd_D <= feWrCmd_pre_Q;
--		
		aFeWrCmd <= aFeWrCmd_Q; 
		bFeWrCmd <= bFeWrCmd_Q;	
		
		
   process(aclk) --change added to bottom register
   begin
      if aclk'event and aclk='1' then
--         if y=0 then
--            y <= YMAX;
--         else
--            y <= y-1;
--         end if; 
 
--		feWrCmd_pre_Q <= feWrCmd_pre_D; 

--		aFeWrCmd_Q <= aFeWrCmd_D;
--		bFeWrCmd_Q <= bFeWrCmd_D;
		
		----------P2-------------
		ext_trg <= p2_trg_i(0);
		ext_trg_r <= ext_trg;
		ext_trg_r2 <= ext_trg_r;
		----------P0------------- added for P0 trig
		p0_ext_trg <= p0_trg_i(0);
		p0_ext_trg_r <= p0_ext_trg;
		p0_ext_trg_r2 <= p0_ext_trg_r;
		----------internal-------
		int_trg_r <= muloth;
		int_trg_r2 <= int_trg_r;
		int_trg_r3 <= int_trg_r2;
		----------TEMP SW-------
		SW_trig_r <= SW_trig;
		SW_trig_r2 <= SW_trig_r;
		SW_trig_r3 <= SW_trig_r2;
		----------P0 SYNC------------- added for P0 SYNC
		p0_SYNC <= p0_trg_i(1); --sync
		p0_SYNC_r <= p0_SYNC;
		p0_SYNC_r2 <= p0_SYNC_r;
		----------P0 TRIG2------------- added for P0 TRIG2
		p0_trig2 <= p0_trg_i(2); --TRIG2
		p0_trig2_r <= p0_trig2;
		p0_trig2_r2 <= p0_trig2_r;
			
      end if;
   end process;	
 ---------------------------------------------------------------------------------  
 ---------------------------------------------------------------------------------

---------------------------------------------------------------------------------
--- trig ouit to fe_wrCmd_pre and led
--------------------------------------------------------------------------------- 
  process(aclk,trig_source) -- change removed from process
   begin
		if aclk'event and aclk='1' then
			if (((p0_ext_trg_r2='0' and p0_ext_trg_r='1' and trig_source(1 downto 0)="00") -- trig on p0_trg(0) rising
			   or (SW_trig_r2='0' and SW_trig_r = '1'  and trig_source(1 downto 0)="01")-- TEMP trig on sw  -- y=0 
			   or (int_trg_r3='0' and int_trg_r2='1'   and trig_source(1 downto 0)="10") -- trig on internal multiplicity sum
			   or (ext_trg_r2='0' and ext_trg_r='1'    and trig_source(1 downto 0)="11")) -- trig on p2_trg(0) rising
				and BLOCK_TRIG = '0')
			then 
				--feWrCmd_pre_D <= '1';
				aFeWrCmd_Q <= '1';
				bFeWrCmd_Q <= '1';
				led_trig <= not led_trig;
				OK_trig <= '1';
				--INC_TRIG_CNT <= '1';
				
			else	
				--feWrCmd_pre_D <= '0';
				aFeWrCmd_Q <= '0';
				bFeWrCmd_Q <= '0';
				--INC_TRIG_CNT  <= '0';
				OK_trig <= '0';
         end if;
      end if;
   end process;

		--feWrCmd_pre <= '1' when feWrCmd_pre_D = '1' or  feWrCmd_pre_Q = '1' else '0';

---------------------------------------------------------------------------------
---------------------------------------------------------------------------------

---------------------------------------------------------------------------------
---- clk,sync, trig counts
---------------------------------------------------------------------------------
	
	clk_count_D <= clk_count_Q + 1 when (p_clk_cnt_rst = '0') else
				   X"00000000" 	   when (p_clk_cnt_rst = '1') else
				   clk_count_Q;
--						 
	
--		SYNC_reset <= '0' when (p0_SYNC_r2='0' and p0_SYNC_r='1' and sync_enable = '1') else '1';
--		
-----------
--		SYNC_CNT_STATUS_D <= SYNC_CNT_STATUS_Q + 1 when SYNC_reset = '0'     and p_sync_cnt_rst = '0' else
--									X"00000000"    when p_SYNC_cnt_rst = '1' and sync_reset = '1'     else 
--									SYNC_CNT_STATUS_Q;  	
--	   
  utrig2 : process(aclk) -- change
   begin
			if aclk'event and aclk='1' then
				if (p0_trig2_r2='0' and p0_trig2_r='1') -- trig on p0_trg(2) rising
					then 
						aEvbHold <= '1'; -- trigger
						bEvbHold <= '1';
						INC_TRIG2_CNT <= '1';
					else	
						aEvbHold <= '0'; -- trigger
						bEvbHold <= '0';
						INC_TRIG2_CNT <= '0';
         end if;
      end if;
   end process utrig2; 							
		
		INC_TRIG2_CNT_D <= INC_TRIG2_CNT;
		OK_trig2 <= PINC_TRIG2_CNT_2Q;
		
		TRIG2_CNT_STATUS_D <= TRIG2_CNT_STATUS_Q + 1 when OK_trig2 = '1' and p_trig2_cnt_rst = '0' else
							  X"00000000" 	 		 when p_trig2_cnt_rst = '1' else  
							  TRIG2_CNT_STATUS_Q;
									
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------

---------------------------------------------------------------------------------
---- pulser output 
---------------------------------------------------------------------------------

		go_pulse <= pulser_ctrl(0) when (cwr = '1' and ca = "11010000001011") else '0'; 
		pulser_trig_delay <= pulser_ctrl(1) when (cwr = '1' and ca = "11010000001011") else '0';
		go_pulse_trig <= go_pulse and pulser_trig_delay;

		
	upulse_update: pulse_update generic map (  bitlength => 4 )			-- generate 'hit' pulse
		port map (  
					clk => aclk, 
					reset => RESET, --not RESET_N,
					go_pulse => go_pulse,
					pulse_width => "1001",			-- pulse width is ??? ns
					pulse_out => pulser_out 
				);
									 					 
	pulser_n <= pulser_out;
	
	upulse_delayed: pulse_delayed generic map (   bitlength => 12 )	-- generate delayed 'soft trigger' pulse
		port map ( 
					clk => aclk,
					reset => RESET, --not RESET_N,
					go_pulse => go_pulse_trig, --go_pulse_trig_P, --go_pulse_trig, --not go_pulse, --go_pulse_trig,
					delay_width => pulser_trig_delay_width,	-- delay value from register
					pulse_width => X"004",			-- pulse width is 100 ns
--					delay_out => open,
					pulse_out => pulser_trig 
				);	

---------------------------------------------------------------------------------
---------------------------------------------------------------------------------	
	
---------------------------------------------------------------------------------
---- token passing to main/mezz 
---------------------------------------------------------------------------------	
		  	  
	UTOKEN_PASS : PROC_TOKEN_PASS 
	   PORT map (
					CLK => aclk, --osc_B,
					RESET_N => RESET_N,
					EvbTokIn => aEvbTokIn_Q, --token staus from chain
					TRIG_GO => TRIG_GO, --clk and trigger
					FeRdBusy_n => aFeRdBusy_n_T, -- does FE have data	-- not
					EvbTokOut => aEvbTokOut_T, -- token out untill last FE chip closes loop and clears
					FeRdCmd => aFeRdCmd_T, -- read enable to FE after data is confirmed present by FeReadBusy
					DEC_TRIG_CNT => DEC_TRIG_CNT -- tracking for trig count
				); 
		  
--		  aEvbTokIn_D <= aEvbTokIn;
--		  aEvbTokOut_D <= aEvbTokOut_T;
--		  aEvbTokOut <= aEvbTokOut_Q;
--		  
--		  aFeRdBusy_n_D <= aFeRdBusy_n;
--		  aFeRdBusy_n_T <= not aFeRdBusy_n_Q;
--		  --aFeRdBusy_n_T <= '0' when aFeRdBusy_n_Q = '0' else '1';
--		  
--		  aFeRdCmd_D <= aFeRdCmd_T;
--		  aFeRdCmd <= aFeRdCmd_Q;
		  
	UbTOKEN_PASS : PROC_TOKEN_PASS 
	   PORT map(
					CLK => aclk, --osc_B,
					RESET_N => RESET_N,
					EvbTokIn => bEvbTokIn_Q, 
					TRIG_GO => bTRIG_GO,
					FeRdBusy_n => bFeRdBusy_n_T, -- not
					EvbTokOut => bEvbTokOut_T,
					FeRdCmd => bFeRdCmd_T, 
					DEC_TRIG_CNT => bDEC_TRIG_CNT
			  );
		  
--		  bEvbTokIn_D <= bEvbTokIn;
--		  bEvbTokOut_D <= bEvbTokOut_T;
--		  bEvbTokOut <= bEvbTokOut_Q;
--		  
--		  bFeRdBusy_n_D <= bFeRdBusy_n;	
--		  bFeRdBusy_n_T <= not bFeRdBusy_n_Q;
--		  --bFeRdBusy_n_T <= '0' when bFeRdBusy_n_Q = '0' else '1';
--		
--		  bFeRdCmd_D <= bFeRdCmd_T;
--		  bFeRdCmd <= bFeRdCmd_Q;
		  
	token_REG : process (aclk)
	begin
		if (aclk = '1' and aclk'event) then --aclk
		
		  aEvbTokIn_D <= aEvbTokIn;
		  aEvbTokOut_D <= aEvbTokOut_T;
		  aEvbTokOut <= aEvbTokOut_Q;
		  
		  aFeRdBusy_n_D <= aFeRdBusy_n;
		  aFeRdBusy_n_T <= not aFeRdBusy_n_Q;
		  --aFeRdBusy_n_T <= '0' when aFeRdBusy_n_Q = '0' else '1';
		  
		  aFeRdCmd_D <= aFeRdCmd_T;
		  aFeRdCmd <= aFeRdCmd_Q;

		  bEvbTokIn_D <= bEvbTokIn;
		  bEvbTokOut_D <= bEvbTokOut_T;
		  bEvbTokOut <= bEvbTokOut_Q;
		  
		  bFeRdBusy_n_D <= bFeRdBusy_n;	
		  bFeRdBusy_n_T <= not bFeRdBusy_n_Q;
		  --bFeRdBusy_n_T <= '0' when bFeRdBusy_n_Q = '0' else '1';
		
		  bFeRdCmd_D <= bFeRdCmd_T;
		  bFeRdCmd <= bFeRdCmd_Q;
					
		end if;
	end process token_REG;
		  
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-----------------------evvb loading--------------------------------------------
-------------------------------------------------------------------------------   

--		INC_TRIG_CNT_D <= INC_TRIG_CNT;	
--	   OK_trig <= INC_TRIG_CNT_Q;
--		
--		DEC_TRIG_BUF1_D <= DEC_TRIG_CNT; 
--		PDEC_TRIG_CNT  <= DEC_TRIG_BUF1_Q;
--		
--		bDEC_TRIG_BUF1_D <= bDEC_TRIG_CNT;
--		bPDEC_TRIG_CNT  <=  bDEC_TRIG_BUF1_Q;
--
		TRIG_GO <= '1'  when (TRIG_CNT_Q > 0  and aEvbTokIn_Q = '0') else '0'; 
		bTRIG_GO <= '1' when (bTRIG_CNT_Q > 0 and bEvbTokIn_Q = '0') else '0';
		
		TRIG_CNT_D <= TRIG_CNT_Q + 1 when OK_trig = '1' 	  and PDEC_TRIG_CNT = '0' else 
		              TRIG_CNT_Q - 1 when PDEC_TRIG_CNT = '1' and OK_trig = '0'       else 
		              TRIG_CNT_Q;
						  
		bTRIG_CNT_D <= bTRIG_CNT_Q + 1 when OK_trig = '1' 		 and bPDEC_TRIG_CNT = '0' else 
		               bTRIG_CNT_Q - 1 when bPDEC_TRIG_CNT = '1' and OK_trig = '0' 		  else 
		               bTRIG_CNT_Q;
	
---------------------------------------------------------------------------------
---------------------------------------------------------------------------------

-------------------------------------------------------------------------------		
-----------------------Daisy Chain FIFO----------------------------------------
-------------------------------------------------------------------------------	
--		aEvbD_D <= aEvbD;
--		aEvbD_2_D <= aEvbD_Q;
--		adaisy_wr_en <= aEvbD_2_Q(16); 	  
		
		uAdaisy : new_daisy_4096 -- 32768 16384
		PORT map (
					rst 	=> RESET, --not RESET_N, 
					wr_clk 	=> aclk,
					rd_clk 	=> aclk,
					wr_en 	=> aEvbD_Q(16), --adaisy_wr_en,
					din 	=> aEvbD_Q(15 downto 0),
					rd_en 	=> aevbd_rd_en, 
					dout 	=> afD,
					full 	=> open,
					empty 	=> aempty_D --aempty_Q --aempty_D
				);
				
--		afD_D <= afD;

--		bEvbD_D <= bEvbD;
--		bEvbD_2_D <= bEvbD_Q;	
--		bdaisy_wr_en <= bEvbD_2_Q(16); 
				
		uBdaisy : new_daisy_4096 -- 32768 16384
		PORT map (
					rst 	=> RESET, --not RESET_N, 
					wr_clk 	=> aclk,
					rd_clk 	=> aclk,
					wr_en 	=> bEvbD_Q(16), --bdaisy_wr_en,
					din 	=> bEvbD_Q(15 downto 0),
					rd_en 	=> bevbd_rd_en, 
					dout 	=> bfD,
					full 	=> open,
					empty 	=> bempty_D --bempty_Q --bempty_D
				);
				
--		bfD_D <= bfD;

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
		
-------------------------------------------------------------------------------
-----------------------Event TRIG COUNT----------------------------------------
-------------------------------------------------------------------------------
		Event_TRIG_CNT_D <= Event_TRIG_CNT_Q + 1 when (OK_trig = '1' and DEC_Evt_Trig_cnt = '0') else
							Event_TRIG_CNT_Q - 1 when (OK_trig = '0' and DEC_Evt_Trig_cnt = '1') else
							Event_TRIG_CNT_Q;
	
	   --Event_Trig_Go <= '1' when (Event_TRIG_CNT_Q > 0 and aempty = '0') else '0'; --TRIG_CNT_D	
		Event_Trig_Go <= '1' when (Event_TRIG_CNT_Q > 0 and aempty_Q = '0') else '0'; -- and aempty_Q = '0' 
			
		TRIG_CNT_STATUS_D <= TRIG_CNT_STATUS_Q + 1 when OK_trig = '1' and p_trig_cnt_rst = '0' else
							      X"00000000" 		    when p_trig_cnt_rst = '1' else 
								   TRIG_CNT_STATUS_Q;
	
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------	
-----------------------CHP EV COUNT--------------------------------------------
-------------------------------------------------------------------------------						

		chip_ev_cnt_D <= chip_ev_cnt_Q + 1 when INC_chip_ev = '1' and Clear_chip_ev = '0' else --INC_chip_ev = '1'
						X"0"			   when Clear_chip_ev = '1' and INC_chip_ev = '0' else --INC_chip_ev = '1'
 						chip_ev_cnt_Q;

		Event_cnt_D <= Event_cnt_Q + 1 when INC_Event_cnt = '1' else --INC_TRIG_CNT = '1'
						"000000"& X"0000" when Block_Trail_GO2_Q = '1' else  --INC_TRIG_CNT = '1'	  and INC_Event_cnt = '0' 
 						Event_cnt_Q;
					

		Event_Done <= '1' when 	chip_ev_cnt_Q = X"c" else '0';	--chip_ev_cnt_Q

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------	
-------------------------------------------------------------------------------		
-----------------------DATA FORMAT---------------------------------------------
-------------------------------------------------------------------------------	
-----------------------evbd controls-------------------------------------------
-------------------------------------------------------------------------------	

		A_GO <= '1' when (aempty_Q = '0' and 
					   (chip_ev_cnt_Q = X"0" or chip_ev_cnt_Q = X"1" or
						chip_ev_cnt_Q = X"4" or chip_ev_cnt_Q = X"5" or
						chip_ev_cnt_Q = X"8" or chip_ev_cnt_Q = X"9")) 
						else '0';
						
		B_GO <= '1' when (bempty_Q = '0' and 
						(chip_ev_cnt_Q = X"2" or chip_ev_cnt_Q = X"3" or
						 chip_ev_cnt_Q = X"6" or chip_ev_cnt_Q = X"7" or
						 chip_ev_cnt_Q = X"a" or chip_ev_cnt_Q = X"b"))
						 else '0';
		
------------------------------------------------------------------------------------				

--		slot_id <= "11111";	-- MUX ON MAIN
--		data_format <= "000";
--		block_number <= "0000001"; -- MUX ON MAIN
		
--		--BLOCK_HEADER <= X"4" & "1" & X"0" & slot_id & X"2" & data_format & block_number_Q & BLOCK_SIZE(7 downto 0); 
--		BLOCK_HEADER <= "0100100001111100100000000001" & BLOCK_SIZE(7 downto 0);
--		Filler_Word <= X"0FBADBEEF";
--		--BLOCK_TRAILER<= X"8" & "1" & X"1" & slot_id & word_count; 
--		BLOCK_TRAILER<= "10001000111111" & word_count;


-- CRAZY CHANGE FOR 16 to 18 BIT CONVERSION THHING
	process (aclk) 
		begin
		if (aclk = '1' and aclk'event) then
			if (Block_Header_GO1 = '1') then 
					fe_data_out_D <= BLOCK_HEADER(31 downto 16);			
				elsif (Block_Header_GO2 = '1') then 
					fe_data_out_D <= BLOCK_HEADER(15 downto 0);
				elsif (A_SEL = '1') then 
					fe_data_out_D <= afD;					
				elsif (B_SEL = '1') then 
					fe_data_out_D <= bfD;					
				elsif (Block_Trail_GO1 = '1') then 
					fe_data_out_D <= BLOCK_TRAILER(31 downto 16);					
				elsif (Block_Trail_GO2 = '1') then 
					fe_data_out_D <= BLOCK_TRAILER(15 downto 0);					
				elsif (Filler_Word_GO1 = '1') then 
					fe_data_out_D <= Filler_Word(31 downto 16);					
				elsif (Filler_Word_GO2 = '1') then 
					fe_data_out_D <= Filler_Word(15 downto 0);					
				else
					fe_data_out_D <= (others => '0');
			end if;		
		end if;
	end process; 
	

--	fe_data_out_D <= BLOCK_HEADER(31 downto 16) when Block_Header_GO1 = '1' else			
--					BLOCK_HEADER(15 downto 0)when Block_Header_GO2 = '1' else 
--					afD when A_SEL = '1' else					
--					bfD when B_SEL = '1' else					
--					BLOCK_TRAILER(31 downto 16) when Block_Trail_GO1 = '1' else					
--					BLOCK_TRAILER(15 downto 0) when Block_Trail_GO2 = '1' else					
--					Filler_Word(31 downto 16) when Filler_Word_GO1 = '1' else					
--					Filler_Word(15 downto 0) when Filler_Word_GO2 = '1' else					
--					others => '0');

		EVENT_TRAIL_Kick <= '1' when (A_Trailer = '1' or B_Trailer = '1') else '0'; --chip_ev_cnt_Q /= X"B" and 
		dontWrite_D <= '1' when  EVENT_TRAIL_Kick = '1' else '0';
		dontWrite <= '1' when (dontWrite_D ='1' or dontWrite_Q = '1') else '0';
	
		fWen_n_D <= '0' when (FWEN ='1' and dontWrite = '0') else '1'; -- change for head/trail kick 
		--fWen_n_D <= '0' when FWEN = '1' else '1'; -- change for head/trail kick
		
		--fWen_n_2D <= fWen_n_Q;
		fWen_n <= fWen_n_2Q when fWen_n_2Q_b = '0' else '1';  
			   
		--fDout <= fe_data_out_Q;

---------------------------------------------------------------------------		
----------EVEN odd counts for output and kicking out headers trailers -----
---------------------------------------------------------------------------

		EVEN_ODD_cnt_D <= EVEN_ODD_cnt_Q + 1 when fWen_n_Q = '0' 			else --FWEN CHANGE
								X"0"			 	 	 when INC_Blk_Evt_Cnt_Q = '1' else 
								EVEN_ODD_cnt_Q;  
						  

		word_count_D <= word_count_Q + 1 when word_cnt = '1' 		 	  else
							 X"00000"&"00"	 	when Block_Trail_GO2_Q = '1' else 
							 word_count_Q;					
						
		word_count <= word_count_Q + 1; -- 16 bit words real value divided by 2
	
		--A_Trailer <= '1' when (afD = x"E800" and EVEN_ODD_cnt_D(0) = '1') else '0';  
  		--B_Trailer <= '1' when (bfD = x"E800" and EVEN_ODD_cnt_D(0) = '1') else '0';	
			  
		A_Trailer <= '1' when (afD = x"E800" and word_count_D(0) = '1') else '0';  
  		B_Trailer <= '1' when (bfD = x"E800" and word_count_D(0) = '1') else '0';	
			  
		EVEN <= '1' when EVEN_ODD_cnt_Q(1) = '0' else '0';	  

--		EVEN_ODD_cnt_D <= EVEN_ODD_cnt_Q + 1 when fWen_n_D = '0' 		  else
--						  X"0"			 	 when Block_Trail_GO2_Q = '1' else 
--						  EVEN_ODD_cnt_Q;  
--						  
--
--		word_count_D <= word_count_Q + 1 when word_cnt = '1' 		 else
--						X"00000"&"00"	 when Block_Trail_GO2_Q = '1' else 
-- 						word_count_Q;					
--						
--		word_count <= word_count_Q + 1; -- 16 bit words real value divided by 2
--	
--		A_Trailer <= '1' when (afD(15 downto 8) = x"E8" and EVEN_ODD_cnt_Q(0) = '1') else '0';  
--  		B_Trailer <= '1' when (bfD(15 downto 8) = x"E8" and EVEN_ODD_cnt_Q(0) = '1') else '0';	
--			  
--		EVEN <= '1' when EVEN_ODD_cnt_Q(1) = '0' else '0';	  
			
---------------------------------------------------------------------------
---------------------------------------------------------------------------
		block_number_D <= block_number_Q + 1 when (Block_Trail_GO2_D = '1' and Block_Trail_GO2_Q = '0') else --change --INC_blk_number
								block_number_Q;
								
		Block_Done <= '1' when Event_cnt_Q = BLOCK_SIZE(21 downto 0) else '0'; 	 							
								
	uEVBD_MAIN_FIFO : EVBD_MAIN_FIFO 
		PORT map (
					CLK => aclk, 
					RESET_N => RESET_N, --RESET, --not RESET_N,
					A_GO => A_GO,
					A_Trailer => A_Trailer,
					B_GO => B_GO,
					B_Trailer => B_Trailer,
					Block_Done => Block_Done,
					EVEN => EVEN,
					Event_Done => Event_Done,
					Event_Trig_Go => Event_Trig_Go,
					A_SEL => A_SEL,
					aevbd_rd_en => aevbd_rd_en, 
					B_SEL => B_SEL,
					bevbd_rd_en => bevbd_rd_en, 
					Block_Header_Go1 => Block_Header_GO1,
					Block_Header_Go2 => Block_Header_GO2,
					Block_Trail_GO1 => Block_Trail_GO1,
					Block_Trail_GO2 => Block_Trail_GO2,
					Clear_chip_ev => Clear_chip_ev,
					DEC_Evt_Trig_cnt => DEC_Evt_Trig_cnt,
					Filler_Word_GO1 => Filler_Word_GO1,
					Filler_Word_GO2 => Filler_Word_GO2,
					FWEN_N => FWEN,
					word_cnt => word_cnt,
					INC_chip_ev => INC_chip_ev,
					INC_Event_cnt => INC_Event_cnt
				);

--		Block_Trail_GO2_D <= Block_Trail_GO2;

----------sending block count to MAIN---------------------------------------------------------------------

		-- registering for 3 clks at 125Mhz to widen pulse for edge detection on MAIN(80Mhz clk) 	
--		INC_Blk_Evt_Cnt_D <= Block_Trail_GO2_Q; --INC_Blk_Evt_Cnt --change
--		INC_Blk_Evt_Cnt_2D <= INC_Blk_Evt_Cnt_Q;
		
		--p2v_spare1 <= '1' when (Block_Trail_GO2_Q = '1' or INC_Blk_Evt_Cnt_D = '1' or INC_Blk_Evt_Cnt_Q = '1' or INC_Blk_Evt_Cnt_2D = '1' or INC_Blk_Evt_Cnt_2Q = '1') else '0';
		p2v_spare1 <= '1' when (INC_Blk_Evt_Cnt_Q = '1' or INC_Blk_Evt_Cnt_2D = '1' or INC_Blk_Evt_Cnt_2Q = '1') else '0';
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------				

   		--BLOCK_HEADER <= X"4" & "1" & X"0" & slot_id & X"2" & data_format & block_number_Q & BLOCK_SIZE(7 downto 0); 
		BLOCK_HEADER <= "0100100001111100100000000001" & BLOCK_SIZE(7 downto 0);
		Filler_Word <= X"0FBADBEEF";
		--BLOCK_TRAILER<= X"8" & "1" & X"1" & slot_id & word_count; 
		BLOCK_TRAILER<= "10001000111111" & word_count;

--	IO_REG : process (aclk)
--	begin
--		if (aclk = '1' and aclk'event) then --aclk
--		
----			fMRst_n <= RESET_N;
----			fLoad <= fcontrol; --00A1 D010, used for main fifo load 
----			fLoad_n <= not fLoad; -- logic conversion  
--			
--			--BLOCK_HEADER <= X"4" & "1" & X"0" & slot_id & X"2" & data_format & block_number_Q & BLOCK_SIZE(7 downto 0); 
--			BLOCK_HEADER <= "0100100001111100100000000001" & BLOCK_SIZE(7 downto 0);
--			Filler_Word <= X"0FBADBEEF";
--			--BLOCK_TRAILER<= X"8" & "1" & X"1" & slot_id & word_count; 
--			BLOCK_TRAILER<= "10001000111111" & word_count;
--					
--		end if;
--	end process IO_REG;
				
	REG : process (aclk, RESET_N) -- have to figure out reset stuff later ...and clk sync etc... p2v_spare0
      begin
        if RESET_N = '0' then 
			
--			afD_Q <= (others => '0');
--			bfD_Q <= (others => '0');
			
			aEvbD_Q <= (others => '0');
			--aEvbD_2_Q <= (others => '0'); 
			
			bEvbD_Q <= (others => '0');
			--bEvbD_2_Q <= (others => '0');
			
			--INC_TRIG_CNT_Q  <= '0';
			INC_TRIG2_CNT_Q  <= '0';
			
			DEC_TRIG_BUF1_Q <= '0';
			--DEC_TRIG_BUF2_Q <= '0';
			bDEC_TRIG_BUF1_Q <= '0';
			--bDEC_TRIG_BUF2_Q <= '0';
			
			--DEC_Evt_TRIG_BUF1_Q <= '0';
			--DEC_Evt_TRIG_BUF2_Q <= '0'; 
			
			TRIG_CNT_Q <= (others => '0');
			bTRIG_CNT_Q <= (others => '0');
			Event_TRIG_CNT_Q <= (others => '0');
			
			--SYNC_CNT_STATUS_Q <= (others => '0');
			
--			aFeWrCmd_Q <= '0';
--			bFeWrCmd_Q <= '0';
--			feWrCmd_pre_Q <= '0';
			
			go_pulse_trig_Q <= '0';
			
--			clk_count_Q <= (others => '0');
			
			INC_Blk_Evt_Cnt_Q <= '0';
			INC_Blk_Evt_Cnt_2Q <= '0'; 
-------------------------------------------------------------
			aevbd_rd_en_Q <= '0';
			bevbd_rd_en_Q <= '0';
			fWen_n_Q <= '1';
			fWen_n_2Q_b <= '1';
			fWen_n_2Q <= '1';
			--fe_data_out_Q <= (others => '0'); --change 
			chip_ev_cnt_Q <= (others => '0');
			Event_cnt_Q <= (others => '0');
			--INC_chip_ev1_Q <= '0';
			--INC_chip_ev2_Q <= '0';
			
			TRIG_CNT_STATUS_Q <= (others => '0');
			TRIG2_CNT_STATUS_Q <= (others => '0');
			
			EVEN_ODD_cnt_Q <= (others => '0');
			word_count_Q <= (others => '0');
			
--			kick_EVEN_ODD_cnt_Q <= (others => '0');
--			kick_EVEN_ODD_cnt_2Q <= (others => '0');
			dontWrite_Q <= '0';
--			
--			dontWriteTime_Q <= '0';
			
			--aAF_n_Q <= '1'; --change, no longer used for write enable
			--bAF_n_Q <= '1'; 
			
			aFeRdBusy_n_Q <= '1';
			aFeRdCmd_Q <= '0';
			bFeRdBusy_n_Q <= '1';
			bFeRdCmd_Q <= '0';
			
			aEvbTokIn_Q <= '0';
			bEvbTokIn_Q <= '0';
			
			aEvbTokOut_Q <= '0';
			aEvbTokOut_Q_B <= '0';
			
			bEvbTokOut_Q <= '0';
			bEvbTokOut_Q_B <= '0';
			
			--PINC_TRIG_CNT_Q <= '0';
			--PINC_TRIG_CNT_2Q <= '0';
			
			PINC_TRIG2_CNT_Q <= '0';
			PINC_TRIG2_CNT_2Q <= '0';
			
			block_number_Q <= "0000001";
		  
			Block_Trail_GO2_Q <= '0';
			
			--aempty_Q <= '1';
		  
        elsif (aclk = '1' and aclk'event) then 
		  
--			afD_Q <= afD_D;
--			bfD_Q <= bfD_D;
 						
			--INC_TRIG_CNT_Q  <= INC_TRIG_CNT_D;
			INC_TRIG2_CNT_Q  <= INC_TRIG2_CNT_D;
			
			DEC_TRIG_BUF1_Q <= DEC_TRIG_BUF1_D;
			--DEC_TRIG_BUF2_Q <= DEC_TRIG_BUF2_D;
			bDEC_TRIG_BUF1_Q <= bDEC_TRIG_BUF1_D;
			--bDEC_TRIG_BUF2_Q <= bDEC_TRIG_BUF2_D;
			
			--DEC_Evt_TRIG_BUF1_Q <= DEC_Evt_TRIG_BUF1_D;
			--DEC_Evt_TRIG_BUF2_Q <= DEC_Evt_TRIG_BUF2_D;
			
			TRIG_CNT_Q <= TRIG_CNT_D;
			bTRIG_CNT_Q <= bTRIG_CNT_D;
			Event_TRIG_CNT_Q <= Event_TRIG_CNT_D;
			
			SYNC_CNT_STATUS_Q <= SYNC_CNT_STATUS_D;
			
			go_pulse_trig_Q <= go_pulse_trig_D;
			go_pulse_trig_2Q <= go_pulse_trig_2D;
			
--			clk_count_Q <= clk_count_D;	

			Block_Trail_GO2_D <= Block_Trail_GO2;
			Block_Trail_GO2_Q <= Block_Trail_GO2_D;

			INC_Blk_Evt_Cnt_D <= Block_Trail_GO2_Q; --INC_Blk_Evt_Cnt --change 
			INC_Blk_Evt_Cnt_Q <= INC_Blk_Evt_Cnt_D;	
			INC_Blk_Evt_Cnt_2D <= INC_Blk_Evt_Cnt_Q;
			INC_Blk_Evt_Cnt_2Q <= INC_Blk_Evt_Cnt_2D;
			
-----------------------------------------------------------
			aevbd_rd_en_Q <= aevbd_rd_en_D;
			bevbd_rd_en_Q <= bevbd_rd_en_D;

			chip_ev_cnt_Q <= chip_ev_cnt_D;
			Event_cnt_Q <= Event_cnt_D;
			--INC_chip_ev1_Q <= INC_chip_ev1_D;
			--INC_chip_ev2_Q <= INC_chip_ev2_D;
			
			TRIG_CNT_STATUS_Q <= TRIG_CNT_STATUS_D;
			TRIG2_CNT_STATUS_Q <= TRIG2_CNT_STATUS_D;
			
			EVEN_ODD_cnt_Q <= EVEN_ODD_cnt_D;
			word_count_Q <= word_count_D;
			
--			kick_EVEN_ODD_cnt_Q <= kick_EVEN_ODD_cnt_D;
--			kick_EVEN_ODD_cnt_2Q <= kick_EVEN_ODD_cnt_2D;
			dontWrite_Q <= dontWrite_D;
--			
--			dontWriteTime_Q <= dontWriteTime_D;
--			dontWriteTime_2Q <= dontWriteTime_2D;
--			dontWriteTime_3Q <= dontWriteTime_3D;
			
			--aAF_n_Q <= aAF_n_D;
			--bAF_n_Q <= bAF_n_D;
			
			aFeRdBusy_n_Q <= aFeRdBusy_n_D;
			aFeRdCmd_Q <= aFeRdCmd_D;
			bFeRdBusy_n_Q <= bFeRdBusy_n_D;
			bFeRdCmd_Q <= bFeRdCmd_D;
			
			aEvbTokIn_Q <= aEvbTokIn_D;
			bEvbTokIn_Q <= bEvbTokIn_D;
			
			aEvbTokOut_Q <= aEvbTokOut_D;
			bEvbTokOut_Q <= bEvbTokOut_D;
			
			--PINC_TRIG_CNT_Q <= PINC_TRIG_CNT_D;
			--PINC_TRIG_CNT_2Q <= PINC_TRIG_CNT_2D;
			
			PINC_TRIG2_CNT_Q <= PINC_TRIG2_CNT_D;
			PINC_TRIG2_CNT_2Q <= PINC_TRIG2_CNT_2D;
			
			block_number_Q <= block_number_D;
			
			go_pulse_trig_B <= go_pulse_trig_A;
			
			--Block_Trail_GO2_Q <= Block_Trail_GO2_D;
			
----------------------------------------------------------
			aEvbD_D <= aEvbD;	
			aEvbD_Q <= aEvbD_D;
			--aEvbD_2_D <= aEvbD_Q; 
			--aEvbD_2_Q <= aEvbD_2_D; 		
		--adaisy_wr_en <= aEvbD_2_Q(16); 
		
			bEvbD_D <= bEvbD;  
			bEvbD_Q <= bEvbD_D;
			--bEvbD_2_D <= bEvbD_Q;
			--bEvbD_2_Q <= bEvbD_2_D;
		--bdaisy_wr_en <= bEvbD_2_Q(16); 
--------------------------------------------------------------	   
--		  aEvbTokIn_D <= aEvbTokIn;
--		  aEvbTokOut_D <= aEvbTokOut_T;
--		  aEvbTokOut <= aEvbTokOut_Q;
--		  
--		  aFeRdBusy_n_D <= aFeRdBusy_n;
--		  aFeRdBusy_n_T <= not aFeRdBusy_n_Q;
--		 -- aFeRdBusy_n_T <= '0' when aFeRdBusy_n_Q = '0' else '1';
--		  
--		  aFeRdCmd_D <= aFeRdCmd_T;
--		  aFeRdCmd <= aFeRdCmd_Q;
----
--		  bEvbTokIn_D <= bEvbTokIn;
--		  bEvbTokOut_D <= bEvbTokOut_T;
--		  bEvbTokOut <= bEvbTokOut_Q;
--		  
--		  bFeRdBusy_n_D <= bFeRdBusy_n;
--		  bFeRdBusy_n_T <= not bFeRdBusy_n_Q;
--		  --bFeRdBusy_n_T <= '0' when bFeRdBusy_n_Q = '0' else '1';
--		
--		  bFeRdCmd_D <= bFeRdCmd_T;
--		  bFeRdCmd <= bFeRdCmd_Q;
-------------------------------------------------------------
		--INC_TRIG_CNT_D <= INC_TRIG_CNT;	
	   --OK_trig <= INC_TRIG_CNT_Q;
		
		DEC_TRIG_BUF1_D <= DEC_TRIG_CNT; 
		PDEC_TRIG_CNT  <= DEC_TRIG_BUF1_Q;
		
		bDEC_TRIG_BUF1_D <= bDEC_TRIG_CNT;
		bPDEC_TRIG_CNT  <=  bDEC_TRIG_BUF1_Q;
-------------------------------------------------------------
		aempty_Q <= aempty_D;
		bempty_Q <= bempty_D;
		
		aFeRdStart_Q <= aFeRdStart_D; -- out to FE, was p2v_spare0
		bFeRdStart_Q <= bFeRdStart_D;
--------------------------------------------------------------		

		fWen_n_Q <= fWen_n_D; 
		fWen_n_2D <= fWen_n_Q; 

		--fWen_n_Q_b <= fWen_n_D;
		fWen_n_2Q_b <= fWen_n_2D;
		fWen_n_2Q <= fWen_n_2D;
		--fWen_n_3Q_b <= fWen_n_3D;
		--fWen_n_3Q <= fWen_n_3D;

		fe_data_out_Q <= fe_data_out_D;	
		--fe_data_out_2Q <= fe_data_out_2D;
		fe_data_out_2Q <= fe_data_out_Q;
		--fDout(15 downto 0) <= fe_data_out_2Q;
		
		aFeRdErr_n_Q <= aFeRdErr_n;
		bFeRdErr_n_Q <= bFeRdErr_n;	
         end if;
end process REG;	

		fDout(15 downto 0) <= fe_data_out_2Q;

end architecture processor_0;




--		kick_EVEN_ODD_cnt_D <= kick_EVEN_ODD_cnt_Q + 1 when (FWEN = '1' and dontWrite = '0') else
--									  X"0"			   		  when DEC_Event_cnt = '1' else 
--									  kick_EVEN_ODD_cnt_Q;
									  
		--kick_EVEN_ODD_cnt_2D <= kick_EVEN_ODD_cnt_Q;
						
		--EVEN <= '1' when kick_EVEN_ODD_cnt_Q(1) = '0' else '0';
		--EVEN <= '1' when kick_EVEN_ODD_cnt_2Q(1) = '0' else '0';		


--		EVEN_ODD_cnt_D <= EVEN_ODD_cnt_Q + 1   when FWEN = '1' and DEC_Event_cnt = '0' else
--								X"00000000"			   when DEC_Event_cnt = '1' and FWEN = '0' else 
--								EVEN_ODD_cnt_Q;

		
--		A_Header <= '1' when (afD(15 downto 11) = x"9" & "0" and EVEN_ODD_cnt_D(0) = '1') else '0';
--		B_Header <= '1' when (bfD(15 downto 11) = x"9" & "0" and EVEN_ODD_cnt_D(0) = '1') else '0';

--		A_Time <= '1' when (afD(15 downto 11) =x"9" & "1"and EVEN_ODD_cnt_D(0) = '1') else '0';
--		B_Time <= '1' when (bfD(15 downto 11) =x"9" & "1" and EVEN_ODD_cnt_D(0) = '1') else '0'; 
 
 		--EVENT_TRAIL_Kick <= '1' when chip_ev_cnt_Q /= X"B" and (A_Trailer_WR = '1' or B_Trailer_WR = '1') else '0';	
		
--		A_Trailer_WR <= '1' when (afD_Q = x"E800" and EVEN_ODD_cnt_Q(0) = '1') else '0';  
--   		B_Trailer_WR <= '1' when (bfD_Q = x"E800" and EVEN_ODD_cnt_Q(0) = '1') else '0';

		
		--EVENT_HEAD_Kick <= '1' when chip_ev_cnt_Q /= X"0" and (A_Header = '1' or B_Header = '1') else '0';
		--EVENT_TIME_Kick <= '1' when chip_ev_cnt_Q /= X"0" and (A_Time = '1' or B_Time = '1') else '0';
		
--		kick_EVEN_ODD_cnt_D <= kick_EVEN_ODD_cnt_Q + 1 when ((FWEN = '1' and dontWrite = '0') and DEC_Event_cnt = '0') else
--							   X"00000000"			   when DEC_Event_cnt = '1' and FWEN = '0' else --Block_Trail_GO2
-- 							   kick_EVEN_ODD_cnt_Q;
 
--dontWrite_D <= '1' when EVENT_HEAD_Kick = '1' or EVENT_TRAIL_Kick = '1' else '0'; -- i only have one event header now
 
--		dontWriteTime_D  <= '1' when EVENT_TIME_Kick = '1' else '0'; -- i only have one event header now
--		dontWriteTime_2D <= dontWriteTime_Q;
--		dontWriteTime_3D <= dontWriteTime_2Q;
--		dontWriteTime <= '1' when (dontWriteTime_D ='1' or dontWriteTime_Q = '1' or dontWriteTime_2Q = '1' or dontWriteTime_3Q = '1') else '0';
		
--		dontWrite <= '1' when (dontWrite_D ='1' or dontWrite_Q = '1' or dontWriteTime = '1') else '0';

--		
--	fe_data_out_D <= 
--					 BLOCK_HEADER(35 downto 18)  when Block_Header_GO1 = '1' else   
--					 BLOCK_HEADER(17 downto 0) when Block_Header_GO2 = '1' else
--					 -- Event Header	 
--					 --"01" & afD when (A_SEL = '1' and A_Header = '1') else 
--					 --"01" & bfD when (B_SEL = '1' and B_Header = '1') else	 
--					 -- Data Word	 
--					 "00" & afD when (A_SEL = '1') else 
--					 "00" & bfD when (B_SEL = '1') else	
--					 -- Event Trailer	 
--					 --"10" & afD when (A_SEL = '1' and A_Trailer = '1') else 
--					 --"10" & bfD when (B_SEL = '1' and B_Trailer = '1') else	 
--					 BLOCK_TRAILER(35 downto 18) when Block_Trail_GO1 = '1' else 
--					 BLOCK_TRAILER(17 downto 0)  when Block_Trail_GO2 = '1' else
--					 Filler_Word(35 downto 18)   when Filler_Word_GO1 = '1' else 
--					 Filler_Word(17 downto 0)    when Filler_Word_GO2 = '1'
--			  else (others => '0');	