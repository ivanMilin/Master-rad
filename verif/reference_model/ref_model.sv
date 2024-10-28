`include "defines.sv"

module ref_model
(
	input clk,
	input reset
);
	`include "structs.sv"	
	
	// Constant parametes - opcodes for each instruction type
	parameter[6:0] instruction_R_type_opcode = `TYPE_R;
	parameter[6:0] instruction_I_type_opcode = `TYPE_I;
	parameter[6:0] instruction_L_type_opcode = `TYPE_L;
	parameter[6:0] instruction_S_type_opcode = `TYPE_S;
	parameter[6:0] instruction_B_type_opcode = `TYPE_B;
	parameter[6:0] instruction_U_type_opcode = `TYPE_U;
	parameter[6:0] instruction_J_type_opcode = `TYPE_J;
	

	// Control singals (combinational) - for reference model 
	logic [31:0] rdata_ref;
	logic [3:0] alu_op_ref; 
	logic [2:0] mask_ref; 
	logic [2:0] br_type_ref;
	logic [1:0] wb_sel_ref; 
	logic reg_wr_ref; 
	logic sel_A_ref; 
	logic sel_B_ref; 
	logic rd_en_ref; 
	logic wr_en_ref;
	logic [31 : 0] data_from_rf_ref;
	logic [4  : 0] address_from_rf;
	
	// Control signal (clocked values) - for reference model 
	logic [3:0] alu_op_ref_next; 
	logic [2:0] mask_ref_next;
	logic [2:0] mask_ref_next_s; 
	logic [2:0] br_type_ref_next;
	logic [1:0] wb_sel_ref_next; 
	logic reg_wr_ref_next; 
	logic sel_A_ref_next; 
	logic sel_B_ref_next; 
	logic rd_en_ref_next; 
	logic wr_en_ref_next; 
	logic [31:0] address_to_check;
	logic [31:0] previous_instruction;

	// Program counter signal(PC) - Combinational and clocked value
	logic [31:0] index_ref;      // PC out
	logic [31:0] index_ref_next; // PC in 
	logic[31:0] pc_counter_ref;

	//Signals for cheching jump and branch 
	logic jump_ref;
	logic branch_ref;
	logic br_taken_ref;

	// Grey box signals from DUT - will be assigned later in code
	logic [31:0] gb_instruction_ref;
	logic [6:0]  gb_func7_ref;
	logic [2:0]  gb_func3_ref;
	logic [31:0] gb_imm_jump_ref;
	logic [31:0] gb_imm_branch_ref;
	logic [31:0] gb_addr_to_be_stored;
	logic [31:0] gb_pc_index;	
	logic [31:0] gb_pc_index_next;
	logic [31:0] gb_dmem_rdata;
	logic [31:0] gb_data_to_be_stored_in_dmem;
	logic [31:0] gb_data_stored_in_rf;
	logic [31:0] gb_data_from_dmem_to_rf;
	logic [31:0] gb_rd;
	logic [31:0] gb_rs1;
	logic [31:0] gb_rs2;
	logic gb_br_taken;
	logic gb_stall;
	logic [31:0] gb_miss_address;
	logic [ 1:0] gb_cache_hit;

	// Free variables
	logic [31:0] fvar_specific_addr;
	logic [31:0] fvar_specific_addr_q;
	logic [31:0] fvar_specific_addr_q_neg;

	// Data memory signals
	logic [31:0] wdata_ref, wdata_ref_s;
	logic known;
	logic valid, valid_loaded;
	logic [31:0] rdata_to_check, rdata_to_check_seq;
	logic [31:0] dmem_line;

	// Register file signals
	logic [31:0] operand1_ref;
	logic [31:0] operand2_ref;
	logic [31:0] result_ref;
	logic [31:0] result_ref_reg;
	logic [31:0] destination_addr;

	logic [11:0] small_immediate_ref;
	logic [31:0] signed_small_immediate_ref;
	
	logic [19:0] big_immediate_ref;
	logic [31:0] signed_big_immediate_ref;

	typedef enum logic [1:0] {MAIN, WAIT_WRITE} state_t;
    	state_t state, next_state;

	// Structes declaration - will be assigned later in the code
	struct_instruction_R   struct_assignment_R;
	struct_instruction_I_L struct_assignment_I;
	struct_instruction_I_L struct_assignment_L;
	struct_instruction_S_B struct_assignment_S;
	struct_instruction_S_B struct_assignment_B;
	struct_instruction_U_J struct_assignment_U;
	struct_instruction_U_J struct_assignment_J;

	// ================= ASSUMES SECTION ================// 
	// Every assume has its "clone" - due to using both positive and negative edge of clock signal

	// Assumptions for instructions - which opcodes will tool feed? 
	property assume_opcodes;
		@(posedge clk) disable iff(reset) 
		Processor.instruction[6:0] inside {instruction_R_type_opcode,instruction_I_type_opcode,instruction_L_type_opcode,instruction_S_type_opcode,instruction_U_type_opcode,instruction_B_type_opcode,instruction_J_type_opcode};
	endproperty 

	property assume_opcodes_neg;
		@(negedge clk) disable iff(reset) 
		Processor.instruction[6:0] inside {instruction_R_type_opcode,instruction_I_type_opcode,instruction_L_type_opcode,instruction_S_type_opcode,instruction_U_type_opcode,instruction_B_type_opcode,instruction_J_type_opcode};
	endproperty 
	

	// Assumptions for LOAD - Can not load into x0 register and limit address size due to memory limitations
	property assume_load_rs2_not_NULL;
		@(posedge clk) disable iff(reset) 
		Processor.im.instruction[6:0] == instruction_L_type_opcode |-> 
		Processor.im.instruction[11:7] != 'b0 && Processor.im.instruction[31:20] + Processor.rf.registerfile[Processor.im.instruction[19:15]] < 1024 && Processor.im.instruction[14:12] inside {3'b000,3'b001,3'b010,3'b100,3'b101};
	endproperty
	
	property assume_load_rs2_not_NULL_neg;
		@(negedge clk) disable iff(reset) 
		Processor.im.instruction[6:0] == instruction_L_type_opcode |-> 
		Processor.im.instruction[11:7] != 'b0 && Processor.im.instruction[31:20] + Processor.rf.registerfile[Processor.im.instruction[19:15]] < 1024 && Processor.im.instruction[14:12] inside {3'b000,3'b001,3'b010,3'b100,3'b101};
	endproperty
	
	
	// Assumptions for STORE - Can not use address larger than memory size limit 
	property assume_store_less_than_1024;
		@(posedge clk) disable iff(reset)  
		Processor.im.instruction[6:0] == instruction_S_type_opcode |-> 
		{{20{Processor.instruction[31]}} , Processor.im.instruction[31:25] , Processor.im.instruction[11:7]} + Processor.rf.registerfile[Processor.im.instruction[19:15]] < 1024;
	endproperty

	property assume_store_less_than_1024_neg;
		@(negedge clk) disable iff(reset)  
		Processor.im.instruction[6:0] == instruction_S_type_opcode |-> 
		{{20{Processor.instruction[31]}} , Processor.im.instruction[31:25] , Processor.im.instruction[11:7]} + Processor.rf.registerfile[Processor.im.instruction[19:15]] < 1024;
	endproperty


	// Assumptions for R , I and U type - None of these can write values to x0 register	
	property assume_cant_write_to_x0;
		@(posedge clk) disable iff(reset) 
		Processor.im.instruction[6:0] == instruction_R_type_opcode || Processor.im.instruction[6:0] == instruction_I_type_opcode || Processor.im.instruction[6:0] == instruction_U_type_opcode |-> 
		Processor.im.instruction[11:7] != 0;
	endproperty
	
	property assume_cant_write_to_x0_neg;
		@(negedge clk) disable iff(reset) 
		Processor.im.instruction[6:0] == instruction_R_type_opcode || Processor.im.instruction[6:0] == instruction_I_type_opcode || Processor.im.instruction[6:0] == instruction_U_type_opcode |-> 
		Processor.im.instruction[11:7] != 0;
	endproperty

	// Assumptions for free variable to be same during verification process and smaller than memory size limit
	property assume_fvar_limit;
		@(posedge clk) disable iff(reset) 
		fvar_specific_addr < 1024;
	endproperty
	
	property assume_fvar_limit_neg;
		@(negedge clk) disable iff(reset) 
		fvar_specific_addr < 1024;
	endproperty
	
	property assume_fvar_stable;
		@(posedge clk) disable iff(reset) 
		!reset ##1 fvar_specific_addr_q == fvar_specific_addr;
	endproperty
	
	property assume_fvar_stable_neg;
		@(negedge clk) disable iff(reset) 
		!reset ##1 fvar_specific_addr_q_neg == fvar_specific_addr;
	endproperty

	property assume_if_stall_not_null;
		//gb_stall |-> $stable(Processor.im.instruction);
		@(posedge clk) disable iff(reset)
		gb_stall == 1'b1 |-> $stable(Processor.im.instruction)[*2];    //https://verificationacademy.com/forums/t/assertion-using-stable-with/37547/2
	endproperty

	property assume_if_stall_not_null_neg;
		//gb_stall |-> $stable(Processor.im.instruction);
		@(negedge clk) disable iff(reset)
		gb_stall == 1'b1 |-> $stable(Processor.im.instruction)[*2];
	endproperty
	
	property assume_funct3_S_type_opcode;
		@(posedge clk) disable iff(reset)
		Processor.im.instruction[6:0] == instruction_S_type_opcode |-> Processor.im.instruction[14:12] inside {3'b000,3'b001,3'b010};
	endproperty
	
	property assume_funct3_S_type_opcode_neg;
		@(negedge clk) disable iff(reset)
		Processor.im.instruction[6:0] == instruction_S_type_opcode |-> Processor.im.instruction[14:12] inside {3'b000,3'b001,3'b010};
	endproperty
	
	property assume_funct3_L_type_opcode;
		@(posedge clk) disable iff(reset)
		Processor.im.instruction[6:0] == instruction_L_type_opcode |-> Processor.im.instruction[14:12] inside {3'b000,3'b001,3'b010,3'b100,3'b101};
	endproperty
	
	property assume_funct3_L_type_opcode_neg;
		@(negedge clk) disable iff(reset)
		Processor.im.instruction[6:0] == instruction_L_type_opcode |-> Processor.im.instruction[14:12] inside {3'b000,3'b001,3'b010,3'b100,3'b101};
	endproperty

	// Assumptions for instructions - which opcodes will tool feed
	all_types_active            : assume property(assume_opcodes);
	all_types_active_neg        : assume property(assume_opcodes_neg);
		
	// Cant load into x0 register
	load_rs2_not_NULL           : assume property(assume_load_rs2_not_NULL);
	load_rs2_not_NULL_neg       : assume property(assume_load_rs2_not_NULL_neg);
	
	// Memory size limit - set to 1024
	store_less_than_1024        : assume property(assume_store_less_than_1024);
	store_less_than_1024_neg    : assume property(assume_store_less_than_1024_neg);

	// When R or I type are active, you cant write in the x0 register
	cant_write_to_x0            : assume property (assume_cant_write_to_x0);
	cant_write_to_x0_neg        : assume property (assume_cant_write_to_x0_neg);

	// Stabilize the free variable and set it accordingly to memory limitations
	asm_fvar_limit           : assume property(assume_fvar_limit);
	asm_fvar_limit_neg       : assume property(assume_fvar_limit_neg);
	
	asm_fvar_stable          : assume property (assume_fvar_stable);
	asm_fvar_stable_neg      : assume property (assume_fvar_stable_neg);

	asm_if_stall_not_null	  : assume property (assume_if_stall_not_null);
	asm_if_stall_not_null_neg : assume property (assume_if_stall_not_null_neg);

	asm_funct3_S_type_opcode     : assume property (assume_funct3_S_type_opcode);
	asm_funct3_S_type_opcode_neg : assume property (assume_funct3_S_type_opcode_neg);
	
	asm_funct3_L_type_opcode     : assume property (assume_funct3_L_type_opcode);
	asm_funct3_L_type_opcode_neg : assume property (assume_funct3_L_type_opcode_neg);

	// Grey box signals assignment
	assign gb_instruction_ref = Processor.instruction;	
	assign gb_func7_ref 	  = Processor.instruction[31:25];	
	assign gb_func3_ref 	  = Processor.instruction[14:12];	
	assign gb_pc_index 	  	  = Processor.index;
	assign gb_pc_index_next   = Processor.next_index;
	assign gb_stall 	      = Processor.stall;
	assign gb_miss_address	  = Processor.controller_and_cache.miss_address;
	assign gb_cache_hit	  	  = Processor.controller_and_cache.cache_hit;

	assign gb_data_to_be_stored_in_dmem = Processor.B_r;
	assign gb_addr_to_be_stored = Processor.A_r + {Processor.instruction[31:25],Processor.instruction[11:7]};
	assign gb_dmem_rdata 	    = Processor.datamemory.memory[fvar_specific_addr[31:2]]; 

	assign gb_data_stored_in_rf = Processor.rf.registerfile[Processor.instruction[11:7]];
	
	assign gb_rd  = Processor.instruction[11:7];
	assign gb_rs1 = Processor.rf.registerfile[Processor.instruction[19:15]];
	assign gb_rs2 = Processor.rf.registerfile[Processor.instruction[24:20]]; 
	
	assign small_immediate_ref = Processor.B_i; 
	assign big_immediate_ref   = Processor.im.instruction[31:12];
	
	assign signed_small_immediate_ref = $signed(small_immediate_ref);
	assign signed_big_immediate_ref   = $signed(big_immediate_ref);
	
	
	assign gb_imm_jump_ref = Processor.B_i;
	assign gb_br_taken = Processor.br_taken;
	assign gb_imm_branch_ref = Processor.B_i;


	// Helper structures for debug phase - Drag and drop in waveform for easier view
	assign struct_assignment_R = Processor.im.instruction; 
	assign struct_assignment_I = Processor.im.instruction;  
	assign struct_assignment_L = Processor.im.instruction; 
	assign struct_assignment_S = '{{Processor.im.instruction[31:25],Processor.im.instruction[11:7]},Processor.im.instruction[24:20],Processor.im.instruction[19:15],Processor.im.instruction[14:12],Processor.im.instruction[6:0]}; 
	assign struct_assignment_B = '{{Processor.im.instruction[31], Processor.im.instruction[7], Processor.im.instruction[30:25], Processor.im.instruction[11:8]}, Processor.im.instruction[24:20], Processor.im.instruction[19:15],
					Processor.im.instruction[14:12], Processor.im.instruction[6:0]}; 
	assign struct_assignment_U = Processor.im.instruction;
	assign struct_assignment_J = '{{Processor.im.instruction[31] , Processor.im.instruction[19:12] , Processor.im.instruction[20] , Processor.im.instruction[30:21]} , Processor.im.instruction[11:7] , Processor.im.instruction[6:0]};
	//assign address_to_check = Processor.alu_out;

	// ===================== AUX code for DATA MEMORY -  Write data on fvar_specific_addr - location based coupling - STORE INSTRUCTION ======================= // 
	
	always_ff @(negedge clk) begin
		if(reset) begin
			address_to_check <= 'b0; 
			wdata_ref_s 	 <= 'b0;
		end
		else begin 
			if(Processor.instruction[6:0] == instruction_S_type_opcode && (Processor.instruction[14:12] == 3'b000 || Processor.instruction[14:12] == 3'b001 || Processor.instruction[14:12] == 3'b010)) begin
				if(gb_addr_to_be_stored == fvar_specific_addr) begin 
					address_to_check <= gb_addr_to_be_stored;
					wdata_ref_s <= wdata_ref; 
				end 
				else begin
					address_to_check <= address_to_check; 
					wdata_ref_s <= wdata_ref_s;
				end
			end
			else begin
				wdata_ref_s <= wdata_ref_s;
			end
		end  
	end 
	
	always_comb begin
		if(Processor.instruction[6:0] == instruction_S_type_opcode && (Processor.instruction[14:12] == 3'b000 || Processor.instruction[14:12] == 3'b001 || Processor.instruction[14:12] == 3'b010)) begin
			if(gb_addr_to_be_stored == fvar_specific_addr) begin 
				known = 1'b1;
				case(Processor.instruction[14:12])
					3'b000 : begin // Store byte
						case(Processor.datamemory.addr[1:0])
							2'b00: begin
								wdata_ref = {24'b0,gb_data_to_be_stored_in_dmem[7:0]}; // Byte 0
							end
							
							2'b01: begin
							 	wdata_ref = {16'b0,gb_data_to_be_stored_in_dmem[7:0],8'b0}; // Byte 1
							end

							2'b10: begin
								wdata_ref = {8'b0,gb_data_to_be_stored_in_dmem[7:0],16'b0}; // Byte 2
							end

							2'b11: begin 
								wdata_ref = {gb_data_to_be_stored_in_dmem[7:0],24'b0}; // Byte 3								
							end
						endcase
					end

					3'b001: begin // Store halfword
						case(Processor.datamemory.addr[1])
							1'b0: begin
								wdata_ref = {16'b0,gb_data_to_be_stored_in_dmem[15:0]};
							end
		
							1'b1: begin
								wdata_ref = {gb_data_to_be_stored_in_dmem[15:0],16'b0};
							end 
						endcase
					end 

					3'b010: begin // Store word
						wdata_ref = gb_data_to_be_stored_in_dmem;
					end

					default : wdata_ref = 'b0;
				endcase
			end 
			else begin
				known = 1'b0;
				address_to_check = address_to_check; 
				wdata_ref = wdata_ref_s;
			end
		end
		else begin
			known = 1'b0;
			wdata_ref <= wdata_ref_s;
		end
	end

	///////////////////
	always_comb begin
		if (Processor.rd_en)
			dmem_line = Processor.datamemory.memory[fvar_specific_addr[31:2]];
		else
			dmem_line = 0;
	end

	// Helping combinational logic for easier property proof
	always_comb begin
		if(Processor.instruction[6:0] == instruction_S_type_opcode && (Processor.instruction[14:12] == 3'b000 || Processor.instruction[14:12] == 3'b001 || Processor.instruction[14:12] == 3'b010)) begin
			case(Processor.instruction[14:12])
				3'b000 : begin // Store byte				
					case(fvar_specific_addr[1:0])
						2'b00: begin
							rdata_to_check = {24'b0,Processor.datamemory.memory[fvar_specific_addr[31:2]][7:0]}; // Byte 0
							//rdata_to_check = (dmem_line & 32'hFFFFFF00) | {24'b0, Processor.B_r[7:0]};
						end
						
						2'b01: begin
						 	rdata_to_check = {16'b0,Processor.datamemory.memory[fvar_specific_addr[31:2]][15:8],8'b0}; // Byte 1
							//rdata_to_check = (dmem_line & 32'hFFFF00FF) | {16'b0, Processor.B_r[7:0], 8'b0};
						end

						2'b10: begin
							rdata_to_check = {8'b0,Processor.datamemory.memory[fvar_specific_addr[31:2]][23:16],16'b0}; // Byte 2
							//rdata_to_check = (dmem_line & 32'hFF00FFFF) | {8'b0, Processor.B_r[7:0], 16'b0};
						end

						2'b11: begin 
							rdata_to_check = {Processor.datamemory.memory[fvar_specific_addr[31:2]][31:24],24'b0}; // Byte 3	
							//rdata_to_check = (dmem_line & 32'h00FFFFFF) | {Processor.B_r[7:0], 24'b0};							
						end
					endcase
				end

				3'b001: begin // Store halfword
					case(fvar_specific_addr[1])
						1'b0: begin
							rdata_to_check = {16'b0,Processor.datamemory.memory[fvar_specific_addr[31:2]][15:0]};
							//rdata_to_check = (dmem_line & 32'hFFFF0000) | {16'b0, Processor.B_r[15:0]};						
						end

						1'b1: begin
							rdata_to_check = {Processor.datamemory.memory[fvar_specific_addr[31:2]][31:16],16'b0};
							//rdata_to_check = (dmem_line & 32'h0000FFFF) | {Processor.B_r[15:0],16'b0};
						end 
					endcase
				end 

				3'b010: begin // Store word
					rdata_to_check = Processor.datamemory.memory[fvar_specific_addr[31:2]];
					//rdata_to_check = Processor.B_r;
				end

				default : rdata_to_check = 'b0;		 
			endcase
		end
		else begin
			rdata_to_check = rdata_to_check_seq;
		end
	end
	
	
	always_ff @(posedge clk) begin
		if(reset) begin
			rdata_to_check_seq <= 'b0;
		end 
		else begin
			rdata_to_check_seq <= rdata_to_check;
		end
	end
	

	// ====================== AUX code for checking LOAD instruction ========================= //  
	always_comb begin
		valid = 0;
		
		if(Processor.instruction[6:0] == instruction_L_type_opcode) begin
			case(Processor.instruction[14:12])
				// Load byte, halfword, word
				3'b000, 3'b001, 3'b010: begin
					valid = 1;	
				end
				default : valid = 0; 
			endcase
		end
	end
	
	always_ff @(negedge clk) begin
		if(reset) begin
			rdata_ref <= 'b0;
			fvar_specific_addr_q_neg <= 'b0;
		end 
		else begin
			rdata_ref <= Processor.wdata_s;
			fvar_specific_addr_q_neg <= fvar_specific_addr;
		end
	end
	
	
	always_ff @(negedge clk) begin
		if(reset) begin
			data_from_rf_ref <= 'b0;
			valid_loaded <= 1'b0;
		end 
		else begin
			if(valid) begin
				if(gb_stall == 'b0) begin
					valid_loaded <= 1'b1;
					address_from_rf <= Processor.instruction[11:7];
					data_from_rf_ref <= gb_data_stored_in_rf;
				end
			end
		end
	end

	always_ff @(posedge clk) begin
		if(reset) begin
			previous_instruction <= 'b0;
		end 
		else begin
			if(Processor.instruction[6:0] == instruction_L_type_opcode) begin
				previous_instruction <= Processor.instruction;
			end
		end
	end
	
	
	//======================= AUX CODE for checking PROGRAM COUNTER ===================//
	always_comb begin
		jump_ref = 0;
		branch_ref = 0;
	
		if(Processor.instruction[6:0] == instruction_J_type_opcode) begin
			jump_ref = 1;
		end
		else if(Processor.instruction[6:0] == instruction_B_type_opcode) begin
			case(Processor.instruction[14:12]) 
				3'b000: begin
					if(gb_rs1 == gb_rs2) begin
						branch_ref = 1;
					end
					else begin 
						branch_ref = 0;
					end
				end
				3'b001: begin
					if(gb_rs1 != gb_rs2) begin
						branch_ref = 1;
					end
					else begin
						branch_ref = 0;
					end
				end
				3'b100: begin
					if(gb_rs1 < gb_rs2) begin
						branch_ref = 1;
					end
					else begin
						branch_ref = 0;
					end
				end
				3'b101: begin
					if(gb_rs1 >= gb_rs2) begin
						branch_ref = 1;
					end
					else begin
						branch_ref = 0;
					end
				end
				3'b110: begin
					if($signed(gb_rs1) < $signed(gb_rs2)) begin
						branch_ref = 1;
					end
					else begin
						branch_ref = 0;
					end
				end
				3'b111: begin
					if($signed(gb_rs1) >= $signed(gb_rs2)) begin
						branch_ref = 1;
					end
					else begin
						branch_ref = 0;
					end
				end
				default: branch_ref = 0;
			endcase
		end
		else begin
			branch_ref = 0;
			jump_ref   = 0;
		end
		
		br_taken_ref = (branch_ref | jump_ref);
	end
	
	always_ff @(posedge clk) begin
		if(reset) begin
			pc_counter_ref <= 'b0;		
		end
		else begin
			if(Processor.instruction[6:0] == instruction_J_type_opcode && br_taken_ref == 1'b1) begin	// Jump 
				pc_counter_ref <= pc_counter_ref + gb_imm_jump_ref; 
			end
			else if(Processor.instruction[6:0] == instruction_B_type_opcode && br_taken_ref == 1'b1) begin  // Branch
				pc_counter_ref <= pc_counter_ref + gb_imm_branch_ref; 	
			end
			else begin
				if(gb_stall == 'b0) begin
					pc_counter_ref <= pc_counter_ref + 4;							// R,I,L,S,U - Sequential
				end
				else begin
					pc_counter_ref <= pc_counter_ref;
				end
			end
		end
	end
	
	//======================= AUX CODE for checking REGISTER FILE value validity ===================//
	always_comb begin 
		result_ref 	 = 'b0;
		operand1_ref 	 = 'b0;
		operand2_ref 	 = 'b0;
		destination_addr = 'b0;

		case(gb_instruction_ref[6:0])
			instruction_R_type_opcode : begin 
				
				operand1_ref = gb_rs1;
				operand2_ref = gb_rs2;
				destination_addr = gb_rd;

				case(gb_func3_ref) 
					3'b000 : begin		//SUB,ADD 
						if(gb_func7_ref == 7'b0100000) begin
							result_ref = operand1_ref - operand2_ref;
						end 
						else begin
							result_ref = operand1_ref + operand2_ref;
						end
					end
					3'b001: begin		//SLL
							result_ref = operand1_ref << operand2_ref;
					end
					3'b010: begin		//SLT
							result_ref = (operand1_ref < operand2_ref)?1:0;
					end
					3'b011: begin		//SLTU
							result_ref = (operand1_ref < operand2_ref)?1:0;
					end
					3'b100: begin		//XOR
						result_ref = operand1_ref ^ operand2_ref;
					end
					3'b101: begin		//SRA, SRL
						if(gb_func7_ref == 7'b0100000) begin 
							result_ref = operand1_ref >>> operand2_ref;
						end 
						else begin
							result_ref = operand1_ref >> operand2_ref;
						end
					end
					3'b110: begin		//OR
						result_ref = operand1_ref | operand2_ref;
					end
					3'b111: begin		//AND
						result_ref = operand1_ref & operand2_ref;
					end
				endcase
			end
			instruction_I_type_opcode: begin
				operand1_ref = gb_rs1;
				destination_addr = gb_rd;

				case(gb_func3_ref) 
					3'b000 : begin		//ADDI 
						result_ref = operand1_ref + signed_small_immediate_ref;
					end
					3'b001: begin		//SLLI
						if(small_immediate_ref[11:5] == 'b0) begin
							result_ref = operand1_ref << signed_small_immediate_ref;
						end					
					end
					3'b010: begin		//SLTI
						result_ref = (operand1_ref < signed_small_immediate_ref) ? 1 : 0;
					end
					3'b011: begin		//SLTIU
						result_ref = (operand1_ref < signed_small_immediate_ref) ? 1 : 0;
					end
					3'b100: begin		//XORI
						result_ref = operand1_ref ^ signed_small_immediate_ref;
					end
					3'b101: begin		//SRAI, SRLI  
						if(small_immediate_ref == 7'b0100000) begin 
							result_ref = operand1_ref >>> signed_small_immediate_ref;
						end 
						else begin
							result_ref = operand1_ref >> signed_small_immediate_ref;
						end
					end
					3'b110: begin		//ORI
						result_ref = operand1_ref | signed_small_immediate_ref;
					end
					3'b111: begin		//ANDI
						result_ref = operand1_ref & signed_small_immediate_ref;
					end
				endcase
			end
			instruction_U_type_opcode: begin
				destination_addr = gb_rd;
				result_ref = signed_big_immediate_ref << 12;
			end
		endcase
	end 
	
	always_ff @(negedge clk) begin
		if(reset) begin
			result_ref_reg <= 'b0;	
		end 
		else begin
			result_ref_reg <= result_ref;
		end
	end
	
	//================== AUX CODE for checking CONTROLLER SIGNALS values ===================//
	always_ff @(posedge clk) begin	
		if(reset) begin
			index_ref   <= 'b0;	
			alu_op_ref  <= 'b0; 
			mask_ref    <= 'b0; 
			br_type_ref <= 'b0;
			wb_sel_ref  <= 'b0; 
			reg_wr_ref  <= 'b0; 
			sel_A_ref   <= 'b0; 
			sel_B_ref   <= 'b0; 
			rd_en_ref   <= 'b0; 
			wr_en_ref   <= 'b0;
			fvar_specific_addr_q <= 'b0;
		end
		else begin
			index_ref   <= index_ref_next;	
			alu_op_ref  <= alu_op_ref_next; 
			mask_ref    <= mask_ref_next; 
			br_type_ref <= br_type_ref_next;
			wb_sel_ref  <= wb_sel_ref_next; 
			reg_wr_ref  <= reg_wr_ref_next; 
			sel_A_ref   <= sel_A_ref_next; 
			sel_B_ref   <= sel_B_ref_next; 
			rd_en_ref   <= rd_en_ref_next; 
			wr_en_ref   <= wr_en_ref_next;
			fvar_specific_addr_q <= fvar_specific_addr;
		end
	end
	
	always_comb begin
		index_ref_next   = index_ref;	
		alu_op_ref_next  = 'b0;
		mask_ref_next    = 'b0; 
		br_type_ref_next = 'b0;
		wb_sel_ref_next  = wb_sel_ref; 
		reg_wr_ref_next  = reg_wr_ref; 
		sel_A_ref_next   = sel_A_ref; 
		sel_B_ref_next   = sel_B_ref; 
		rd_en_ref_next   = rd_en_ref; 
		wr_en_ref_next   = wr_en_ref;
		
		case(gb_instruction_ref[6:0])
			instruction_R_type_opcode: begin
				reg_wr_ref_next = 1;
	    			sel_A_ref_next  = 1;
	    			sel_B_ref_next  = 0;
	    			rd_en_ref_next  = 0;
	    			wb_sel_ref_next = 0;
				
				case(gb_func3_ref)										
					3'b000: begin if (gb_func7_ref == 7'b0100000) alu_op_ref_next = 9; else alu_op_ref_next = 0; end//sub, add
					3'b001:	alu_op_ref_next = 1;//sll
					3'b010:	alu_op_ref_next = 2;//slt
					3'b011:	alu_op_ref_next = 3;//sltu
					3'b100:	alu_op_ref_next = 4;//xor
					3'b101: begin if (gb_func7_ref == 7'b0100000) alu_op_ref_next = 6; else alu_op_ref_next = 5; end//sra, srl
					3'b110:	alu_op_ref_next = 7;//or
					3'b111:	alu_op_ref_next = 8;//and
				endcase
			end
			
			instruction_I_type_opcode: begin
				reg_wr_ref_next  = 1;
	    			sel_A_ref_next   = 1;
	    			sel_B_ref_next   = 1;
	    			rd_en_ref_next   = 0;
	    			wb_sel_ref_next  = 0;
				
				case (Processor.instruction[14:12])
					3'b000: alu_op_ref_next  = 0;//addi
					3'b001:	alu_op_ref_next  = 1;//slli 
					3'b010:	alu_op_ref_next  = 2;//slti
					3'b011:	alu_op_ref_next  = 3;//sltiu
					3'b100:	alu_op_ref_next  = 4;//xori
					3'b101: begin if (Processor.instruction[31:25] == 7'b0000010) alu_op_ref_next  = 6; else alu_op_ref_next  = 5; end //srai, srli
					3'b110:	alu_op_ref_next  = 7;//ori
					3'b111:	alu_op_ref_next  = 8;//andi
				endcase
			end
			
			instruction_L_type_opcode: begin				
				reg_wr_ref_next = 1;
	    			sel_A_ref_next  = 1;
	    			sel_B_ref_next  = 1;
	    			rd_en_ref_next  = 1;
	    			wr_en_ref_next  = 0;
	    			wb_sel_ref_next = 1;
	    			alu_op_ref_next = 0;
	    			mask_ref_next   = Processor.instruction[14:12];						
			end
			
			instruction_S_type_opcode: begin
				reg_wr_ref_next = 0;
	    			sel_A_ref_next  = 1;
	    			sel_B_ref_next  = 1;
	    			rd_en_ref_next  = 1;
	    			wr_en_ref_next  = 1;
	    			wb_sel_ref_next = 1;
	    			alu_op_ref_next = 0;
	    			mask_ref_next   = Processor.instruction[14:12];						
			end
			
			instruction_B_type_opcode: begin
				reg_wr_ref_next = 0;
	    			sel_A_ref_next  = 0;
	    			sel_B_ref_next  = 1;
	    			rd_en_ref_next  = 0;
	    			wr_en_ref_next  = 0;
	    			wb_sel_ref_next = 0;
	    			alu_op_ref_next = 0;
				br_type_ref_next = Processor.instruction[14:12]; 
			end
			
			instruction_U_type_opcode: begin
				reg_wr_ref_next = 1;
	    			sel_A_ref_next  = 1;
	    			sel_B_ref_next  = 1;
	    			rd_en_ref_next  = 0;
	    			wr_en_ref_next  = 0;
	    			wb_sel_ref_next = 0;
	    			alu_op_ref_next = 10;
			end	
			
			instruction_J_type_opcode: begin				
				reg_wr_ref_next = 1;
	    			sel_A_ref_next  = 0;
	    			sel_B_ref_next  = 1;
	    			rd_en_ref_next  = 0;
	    			wr_en_ref_next  = 0;
	    			wb_sel_ref_next = 2;
	    			alu_op_ref_next = 0;			
			end		
		endcase
	end

	// =============== PROPERTIES SECTION ================ //

	// Controller properties for each instruction type
	property check_instruction_R_type_opcode;
		Processor.instruction[6:0]==instruction_R_type_opcode |=>
		Processor.controller.reg_wr == reg_wr_ref_next  && 
		Processor.controller.sel_A  == sel_A_ref_next   &&
		Processor.controller.sel_B  == sel_B_ref_next   &&
		Processor.controller.rd_en  == rd_en_ref_next   &&
		Processor.controller.wb_sel == wb_sel_ref_next  &&	
		Processor.controller.alu_op == alu_op_ref_next;
	endproperty

	property check_instruction_I_type_opcode;
		Processor.instruction[6:0] == instruction_I_type_opcode |=>
		Processor.controller.reg_wr == reg_wr_ref_next  && 
		Processor.controller.sel_A  == sel_A_ref_next   &&
		Processor.controller.sel_B  == sel_B_ref_next   &&
		Processor.controller.rd_en  == rd_en_ref_next   &&
		Processor.controller.alu_op == alu_op_ref_next  &&
		Processor.controller.wb_sel == wb_sel_ref_next;	
	endproperty

	property check_instruction_L_S_type_opcode;
		(Processor.instruction[6:0] == instruction_L_type_opcode ||
		Processor.instruction[6:0] == instruction_S_type_opcode) |=>
		Processor.controller.reg_wr == reg_wr_ref_next  && 
		Processor.controller.sel_A  == sel_A_ref_next   &&
		Processor.controller.sel_B  == sel_B_ref_next   &&
		Processor.controller.rd_en  == rd_en_ref_next   &&
		Processor.controller.alu_op == alu_op_ref_next  &&
		Processor.controller.wb_sel == wb_sel_ref_next  &&
		Processor.controller.mask == mask_ref_next;	
	endproperty
	
	property check_instruction_U_type_opcode;
		Processor.instruction[6:0] == instruction_U_type_opcode |=>
		Processor.controller.reg_wr == reg_wr_ref_next  && 
		Processor.controller.sel_A  == sel_A_ref_next   &&
		Processor.controller.sel_B  == sel_B_ref_next   &&
		Processor.controller.rd_en  == rd_en_ref_next   &&
		Processor.controller.alu_op == alu_op_ref_next  &&
		Processor.controller.wb_sel == wb_sel_ref_next  &&
		Processor.controller.wr_en ==  wr_en_ref_next;	
	endproperty

	property check_instruction_B_type_opcode;
		Processor.instruction[6:0] == instruction_B_type_opcode |=>
		Processor.controller.reg_wr == reg_wr_ref_next  && 
		Processor.controller.sel_A  == sel_A_ref_next   &&
		Processor.controller.sel_B  == sel_B_ref_next   &&
		Processor.controller.rd_en  == rd_en_ref_next   &&
		Processor.controller.alu_op == alu_op_ref_next  &&
		Processor.controller.wb_sel == wb_sel_ref_next  &&
		Processor.controller.br_type == br_type_ref_next;	
		
	endproperty

	property check_instruction_J_type_opcode;
		Processor.instruction[6:0] == instruction_J_type_opcode |=>
		Processor.controller.reg_wr == reg_wr_ref_next  && 
		Processor.controller.sel_A  == sel_A_ref_next   &&
		Processor.controller.sel_B  == sel_B_ref_next   &&
		Processor.controller.rd_en  == rd_en_ref_next   &&
		Processor.controller.alu_op == alu_op_ref_next  &&
		Processor.controller.wb_sel == wb_sel_ref_next  && 
		Processor.controller.wr_en ==  wr_en_ref_next;	
	endproperty
	
	// Property that checks if reference value of PC is same as PC from DUT
	property check_PC;
		Processor.index == pc_counter_ref;	
	endproperty

	// Property that checks if STORE WORD in data memory and in cache is correct
	property check_data_memory_store_word;
		known && Processor.instruction[14:12] == 3'b010 && fvar_specific_addr == address_to_check && 
		({Processor.im.instruction[31:25],Processor.im.instruction[11:7]} + Processor.im.instruction[19:15]) % 4 == 0  |->
		wdata_ref == rdata_to_check && 
		Processor.controller_and_cache.cache_memory_L1[fvar_specific_addr[7:2]].data == rdata_to_check && 
		Processor.controller_and_cache.cache_memory_L1[fvar_specific_addr[7:2]].tag  == fvar_specific_addr[9:8];
	endproperty
	
	// Property that checks if STORE HALF WORD(upper) in data memory and in cache is correct
	property check_data_memory_store_half_word_upper;
		known && Processor.instruction[14:12] == 3'b001 && fvar_specific_addr == address_to_check && fvar_specific_addr[1] == 1 &&
		({Processor.im.instruction[31:25],Processor.im.instruction[11:7]} + Processor.im.instruction[19:15]) % 2 == 0 |-> 	
		wdata_ref == rdata_to_check && 
		Processor.controller_and_cache.cache_memory_L1[fvar_specific_addr[7:2]].data[31:16] == rdata_to_check[31:16] && 
		Processor.controller_and_cache.cache_memory_L1[fvar_specific_addr[7:2]].tag  == fvar_specific_addr[9:8];
	endproperty

	// Property that checks if STORE HALF WORD(lower) in data memory and in cache is correct
	property check_data_memory_store_half_word_lower;
		known && Processor.instruction[14:12] == 3'b001 && fvar_specific_addr == address_to_check && fvar_specific_addr[1] == 0 && 
		({Processor.im.instruction[31:25],Processor.im.instruction[11:7]} + Processor.im.instruction[19:15]) % 2 == 0 |-> 	
		wdata_ref == rdata_to_check && 
		Processor.controller_and_cache.cache_memory_L1[fvar_specific_addr[7:2]].data[15:0] == rdata_to_check[15:0] && 
		Processor.controller_and_cache.cache_memory_L1[fvar_specific_addr[7:2]].tag  == fvar_specific_addr[9:8];
	endproperty
	
	// Property that checks if STORE BYTE 0 in data memory and in cache is correct
	property check_data_memory_store_byte0;
		known && Processor.instruction[14:12] == 3'b000 && fvar_specific_addr == address_to_check && fvar_specific_addr[1:0] == 2'b00 |-> 	
		wdata_ref == rdata_to_check && 
		Processor.controller_and_cache.cache_memory_L1[fvar_specific_addr[7:2]].data[7:0] == rdata_to_check[7:0] && 
		Processor.controller_and_cache.cache_memory_L1[fvar_specific_addr[7:2]].tag  == fvar_specific_addr[9:8];
	endproperty

	// Property that checks if STORE BYTE 1 in data memory and in cache is correct
	property check_data_memory_store_byte1;
		known && Processor.instruction[14:12] == 3'b000 && fvar_specific_addr == address_to_check && fvar_specific_addr[1:0] == 2'b01 |-> 	
		wdata_ref == rdata_to_check && 
		Processor.controller_and_cache.cache_memory_L1[fvar_specific_addr[7:2]].data[15:8] == rdata_to_check[15:8] && 
		Processor.controller_and_cache.cache_memory_L1[fvar_specific_addr[7:2]].tag  == fvar_specific_addr[9:8];
	endproperty

	// Property that checks if STORE BYTE 2 in data memory and in cache is correct
	property check_data_memory_store_byte2;
		known && Processor.instruction[14:12] == 3'b000 && fvar_specific_addr == address_to_check && fvar_specific_addr[1:0] == 2'b10 |-> 	
		wdata_ref == rdata_to_check && 
		Processor.controller_and_cache.cache_memory_L1[fvar_specific_addr[7:2]].data[23:16] == rdata_to_check[23:16] && 
		Processor.controller_and_cache.cache_memory_L1[fvar_specific_addr[7:2]].tag  == fvar_specific_addr[9:8];
	endproperty

	// Property that checks if STORE BYTE 3 in data memory and in cache is correct
	property check_data_memory_store_byte3;
		known && Processor.instruction[14:12] == 3'b000 && fvar_specific_addr == address_to_check && fvar_specific_addr[1:0] == 2'b11 |-> 	
		wdata_ref == rdata_to_check && 
		Processor.controller_and_cache.cache_memory_L1[fvar_specific_addr[7:2]].data[31:24] == rdata_to_check[31:24] && 
		Processor.controller_and_cache.cache_memory_L1[fvar_specific_addr[7:2]].tag  == fvar_specific_addr[9:8];
	endproperty

	// Property that checks if LOAD in regiseter file is correct
	property check_load_in_rf;
		$rose(valid_loaded) |-> rdata_ref == Processor.rf.registerfile[address_from_rf] ;
	endproperty

	property check_data_from_dmem_to_cache_if_miss; //posedge
		$rose(gb_stall) ##2 Processor.controller_and_cache.state == WAIT_WRITE |=> 
		Processor.controller_and_cache.cache_memory_L1[gb_miss_address[7:0]].valid == 1'b1 &&
		Processor.controller_and_cache.cache_memory_L1[gb_miss_address[7:0]].tag   == gb_miss_address[9:8] &&
		Processor.controller_and_cache.cache_memory_L1[gb_miss_address[7:0]].data  == Processor.datamemory.memory[gb_miss_address];  
	endproperty

	property check_load_hit; //posedge
		Processor.instruction[6:0] == instruction_L_type_opcode && gb_cache_hit == 2'b10 |=>
		Processor.rf.registerfile[previous_instruction[11:7]] == Processor.controller_and_cache.cache_memory_L1[Processor.controller_and_cache.index_in];		
	endproperty

	property check_state_transition_MAIN_WAIT_WRITE;
		Processor.controller_and_cache.state == MAIN && Processor.controller_and_cache.cache_hit == 2'b01 |=> Processor.controller_and_cache.state == WAIT_WRITE;
	endproperty

	property check_state_transition_WAIT_WRITE_MAIN;
		Processor.controller_and_cache.state == WAIT_WRITE |=> Processor.controller_and_cache.state == MAIN;
	endproperty

	// Property that checks if values in register file are correct after R and I and U type instruction
	property check_rf_R_I_U;
		Processor.instruction[6:0] == instruction_R_type_opcode || Processor.instruction[6:0] == instruction_I_type_opcode || Processor.instruction[6:0] == instruction_U_type_opcode |->
		Processor.rf.registerfile[destination_addr] == result_ref_reg;
	endproperty
	
	
	// ===================== ASSERTIONS SECTION ==================== //
 
	// ============ CONTROLLER ASSERTS =========== //
	/*ASSERT PASSED */// assert_instruction_R_type_opcode 	   : assert property(@(posedge clk) check_instruction_R_type_opcode);
	/*ASSERT PASSED */// assert_instruction_I_type_opcode 	   : assert property(@(posedge clk) check_instruction_I_type_opcode);
	/*ASSERT PASSED */// assert_instruction_U_type_opcode 	   : assert property(@(posedge clk) check_instruction_U_type_opcode);
	/*ASSERT PASSED */// assert_check_instruction_B_type_opcode     : assert property(@(posedge clk) check_instruction_B_type_opcode);
	/*ASSERT PASSED */// assert_check_instruction_L_S_type_opcode   : assert property(@(posedge clk) check_instruction_L_S_type_opcode);
	/*ASSERT PASSED */// assert_check_instruction_J_type_opcode     : assert property(@(posedge clk) check_instruction_J_type_opcode);
	
	// ============= PROGRAM COUNTER ASSERTS ============ //
	/*ASSERT PASSED */// assert_check_PC    : assert property(@(posedge clk) check_PC);
	
	// ============= DATA MEMORY ASSERTS ============= //
	//assert_check_data_memory_store_word 	 : assert property(@(posedge clk) check_data_memory_store_word);
	//assert_check_data_memory_store_half_word_upper : assert property(@(posedge clk) check_data_memory_store_half_word_upper);
	//assert_check_data_memory_store_half_word_lower : assert property(@(posedge clk) check_data_memory_store_half_word_lower);
	//assert_check_data_memory_store_byte0 	 	   : assert property(@(posedge clk) check_data_memory_store_byte0);
	//assert_check_data_memory_store_byte1 	 	   : assert property(@(posedge clk) check_data_memory_store_byte1);
	//assert_check_data_memory_store_byte2 	 	   : assert property(@(posedge clk) check_data_memory_store_byte2);
	//assert_check_data_memory_store_byte3 	 	   : assert property(@(posedge clk) check_data_memory_store_byte3);

	// ============= CACHE CONTROLLER ASSERTS ============= //
	//assert_check_data_from_dmem_to_cache_if_miss  : assert property(@(posedge clk) check_data_from_dmem_to_cache_if_miss);
	//assert_check_load_hit						    : assert property(@(posedge clk) check_load_hit);
	//assert_check_state_transition_MAIN_WAIT_WRITE : assert property(@(posedge clk) check_state_transition_MAIN_WAIT_WRITE);
	//assert_check_state_transition_WAIT_WRITE_MAIN : assert property(@(posedge clk) check_state_transition_WAIT_WRITE_MAIN);

	//cover_check_data_memory  : cover property(@(posedge clk) Processor.datamemory.memory[0] == 5); // Additional cover that helped us work out issues with datamemory
	//cover_dmem_cache_data : cover property(@(posedge clk) Processor.datamemory.memory[10] == Processor.controller_and_cache.cache_memory_L1[10].data && 
	//													  Processor.controller_and_cache.cache_memory_L1[10].valid == 1 && 
	//													  Processor.datamemory.memory[10] != 0);

	
	// ============= REGISTER FILE ASSERTS ============ //
	//assert_check_load_in_rf : assert property(@(negedge clk) check_load_in_rf);
	//cover_check_data_memory  : cover property(@(posedge clk) Processor.datamemory.memory[0] == 5); 

	// ============= REGISTER FILE RESULT CHECK  ASSERTS ================ //
	//assert_check_rf_R_I_U : assert property(@(posedge clk) check_rf_R_I_U);
		
endmodule


