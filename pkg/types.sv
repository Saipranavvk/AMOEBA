package riscv_types;

    //------------------------------------------------------------
    // RV64IMAC + Zicsr + Zifencei Types Package
    //
    // This package contains instruction encodings, enums,
    // instruction formats, and architectural constants used
    // throughout the processor.
    //
    // References:
    //   Volume I: RISC-V Unprivileged ISA
    //   Volume II: RISC-V Privileged ISA
    //------------------------------------------------------------

    //------------------------------------------------------------
    // Architectural Parameters
    //------------------------------------------------------------

    /* verilator lint_off VARHIDDEN */
    parameter int XLEN = 64;
    parameter int ILEN = 32;
    /* verilator lint_on VARHIDDEN */

    parameter int REG_ADDR_W = 5;
    parameter int REG_COUNT  = 32;

    parameter int MEM_BYTES = XLEN/8;

    typedef logic [XLEN-1:0] xlen_t;
    typedef logic [31:0]     instr32_t;
    typedef logic [15:0]     instr16_t;
    typedef logic [4:0]      reg_addr_t;

    //------------------------------------------------------------
    // Standard 32-bit Instruction Opcodes
    //
    // instruction[6:0]
    //------------------------------------------------------------

    typedef enum logic [6:0] {

        OP_LOAD        = 7'b0000011,
        OP_MISC_MEM    = 7'b0001111,
        OP_OP_IMM      = 7'b0010011,
        OP_AUIPC       = 7'b0010111,
        OP_OP_IMM_32   = 7'b0011011,
        OP_STORE       = 7'b0100011,
        OP_AMO         = 7'b0101111,
        OP_OP          = 7'b0110011,
        OP_LUI         = 7'b0110111,
        OP_OP_32       = 7'b0111011,
        OP_BRANCH      = 7'b1100011,
        OP_JALR        = 7'b1100111,
        OP_JAL         = 7'b1101111,

        //--------------------------------------------------------
        // CSR / ECALL / EBREAK / MRET / WFI
        //--------------------------------------------------------

        OP_SYSTEM      = 7'b1110011

    } opcode_t;

    //------------------------------------------------------------
    // Compressed Instruction Quadrants
    //
    // instruction[1:0]
    //
    // 00 : Loads, Stores, ADDI4SPN
    // 01 : Arithmetic, Branches, Jumps
    // 10 : Stack operations, JR/JALR, MV/ADD
    // 11 : Standard 32-bit instruction
    //------------------------------------------------------------

    typedef enum logic [1:0] {

        C_QUAD0 = 2'b00,
        C_QUAD1 = 2'b01,
        C_QUAD2 = 2'b10,
        C_QUAD3 = 2'b11

    } c_quadrant_t;

    //------------------------------------------------------------
    // Compressed Opcode Field
    //
    // instruction[15:13]
    //
    // Meaning depends on quadrant.
    //
    // -----------------------------------------------------------
    // Quadrant 0
    // -----------------------------------------------------------
    // 000 C.ADDI4SPN
    // 001 C.FLD
    // 010 C.LW
    // 011 C.LD
    // 100 Reserved
    // 101 C.FSD
    // 110 C.SW
    // 111 C.SD
    //
    // -----------------------------------------------------------
    // Quadrant 1
    // -----------------------------------------------------------
    // 000 C.ADDI / C.NOP
    // 001 C.ADDIW
    // 010 C.LI
    // 011 C.ADDI16SP / C.LUI
    // 100 Misc ALU
    // 101 C.J
    // 110 C.BEQZ
    // 111 C.BNEZ
    //
    // -----------------------------------------------------------
    // Quadrant 2
    // -----------------------------------------------------------
    // 000 C.SLLI
    // 001 C.FLDSP
    // 010 C.LWSP
    // 011 C.LDSP
    // 100 C.JR
    //     C.MV
    //     C.EBREAK
    //     C.JALR
    //     C.ADD
    // 101 C.FSDSP
    // 110 C.SWSP
    // 111 C.SDSP
    //------------------------------------------------------------

    typedef enum logic [2:0] {

        C_OP0 = 3'b000,
        C_OP1 = 3'b001,
        C_OP2 = 3'b010,
        C_OP3 = 3'b011,
        C_OP4 = 3'b100,
        C_OP5 = 3'b101,
        C_OP6 = 3'b110,
        C_OP7 = 3'b111

    } c_opcode_t;

    //------------------------------------------------------------
    // Integer Arithmetic funct3
    //------------------------------------------------------------

    typedef enum logic [2:0] {

        F3_ADD_SUB = 3'b000,
        F3_SLL     = 3'b001,
        F3_SLT     = 3'b010,
        F3_SLTU    = 3'b011,
        F3_XOR     = 3'b100,
        F3_SRL_SRA = 3'b101,
        F3_OR      = 3'b110,
        F3_AND     = 3'b111

    } arith_f3_t;

    //------------------------------------------------------------
    // Branch funct3
    //------------------------------------------------------------

    typedef enum logic [2:0] {

        F3_BEQ   = 3'b000,
        F3_BNE   = 3'b001,
        F3_BLT   = 3'b100,
        F3_BGE   = 3'b101,
        F3_BLTU  = 3'b110,
        F3_BGEU  = 3'b111

    } branch_f3_t;

    //------------------------------------------------------------
    // Load funct3
    //------------------------------------------------------------

    typedef enum logic [2:0] {

        F3_LB   = 3'b000,
        F3_LH   = 3'b001,
        F3_LW   = 3'b010,
        F3_LD   = 3'b011,
        F3_LBU  = 3'b100,
        F3_LHU  = 3'b101,
        F3_LWU  = 3'b110

    } load_f3_t;

    //------------------------------------------------------------
    // Store funct3
    //------------------------------------------------------------

    typedef enum logic [2:0] {

        F3_SB   = 3'b000,
        F3_SH   = 3'b001,
        F3_SW   = 3'b010,
        F3_SD   = 3'b011

    } store_f3_t;

    //------------------------------------------------------------
    // MISC-MEM funct3
    //------------------------------------------------------------

    typedef enum logic [2:0] {

        F3_FENCE   = 3'b000,
        F3_FENCE_I = 3'b001

    } misc_mem_f3_t;

    //------------------------------------------------------------
    // SYSTEM funct3
    //------------------------------------------------------------

    typedef enum logic [2:0] {

        F3_PRIV    = 3'b000,

        F3_CSRRW   = 3'b001,
        F3_CSRRS   = 3'b010,
        F3_CSRRC   = 3'b011,

        F3_CSRRWI  = 3'b101,
        F3_CSRRSI  = 3'b110,
        F3_CSRRCI  = 3'b111

    } system_f3_t;

    //------------------------------------------------------------
    // Standard funct7 values
    //------------------------------------------------------------

    typedef enum logic [6:0] {

        F7_BASE      = 7'b0000000,

        // SUB / SRA
        F7_ALT       = 7'b0100000,

        // Multiply / Divide extension
        F7_MULDIV    = 7'b0000001

    } funct7_t;

    //------------------------------------------------------------
    // RV64 Shift Immediate funct6
    //
    // imm[11:6]
    //------------------------------------------------------------

    typedef enum logic [5:0] {

        SHIFT_SLLI = 6'b000000,

        SHIFT_SRAI = 6'b010000

    } shift_f6_t;

        //============================================================
    // REGISTER FILE DEFINITIONS
    //============================================================

    //------------------------------------------------------------
    // Integer Register ABI Names
    //
    // x0  = zero
    // x1  = ra
    // x2  = sp
    // ...
    //------------------------------------------------------------

    typedef enum logic [4:0] {

        REG_X0  = 5'd0,
        REG_X1  = 5'd1,
        REG_X2  = 5'd2,
        REG_X3  = 5'd3,
        REG_X4  = 5'd4,
        REG_X5  = 5'd5,
        REG_X6  = 5'd6,
        REG_X7  = 5'd7,
        REG_X8  = 5'd8,
        REG_X9  = 5'd9,
        REG_X10 = 5'd10,
        REG_X11 = 5'd11,
        REG_X12 = 5'd12,
        REG_X13 = 5'd13,
        REG_X14 = 5'd14,
        REG_X15 = 5'd15,
        REG_X16 = 5'd16,
        REG_X17 = 5'd17,
        REG_X18 = 5'd18,
        REG_X19 = 5'd19,
        REG_X20 = 5'd20,
        REG_X21 = 5'd21,
        REG_X22 = 5'd22,
        REG_X23 = 5'd23,
        REG_X24 = 5'd24,
        REG_X25 = 5'd25,
        REG_X26 = 5'd26,
        REG_X27 = 5'd27,
        REG_X28 = 5'd28,
        REG_X29 = 5'd29,
        REG_X30 = 5'd30,
        REG_X31 = 5'd31

    } reg_name_t;

    //============================================================
    // PRIVILEGE LEVELS (RV64 Privileged Spec)
    //============================================================

    typedef enum logic [1:0] {

        PRIV_U = 2'b00,   // User mode
        PRIV_S = 2'b01,   // Supervisor mode
        PRIV_M = 2'b11    // Machine mode (no 2'b10 in standard ISA)

    } privilege_t;

    //============================================================
    // SYSTEM INSTRUCTION IMMEDIATE VALUES
    //============================================================
    // Used when opcode = OP_SYSTEM and funct3 = 000
    //============================================================

    typedef enum logic [11:0] {

        SYS_ECALL  = 12'h000,   // environment call
        SYS_EBREAK = 12'h001,   // breakpoint

        SYS_URET   = 12'h002,   // return from user trap
        SYS_SRET   = 12'h102,   // return from supervisor trap
        SYS_MRET   = 12'h302,   // return from machine trap

        SYS_WFI    = 12'h105    // wait for interrupt

    } system_imm_t;

    //============================================================
    // CSR ADDRESS SPACE (ARCHITECTURAL)
    //============================================================
    // Covers User, Supervisor, Machine CSRs
    // RV64 Privileged Architecture 1.12
    //============================================================

    typedef enum logic [11:0] {

        //--------------------------------------------------------
        // USER CSRs
        //--------------------------------------------------------

        CSR_USTATUS      = 12'h000,
        CSR_UIE          = 12'h004,
        CSR_UTVEC        = 12'h005,

        CSR_USCRATCH     = 12'h040,
        CSR_UEPC         = 12'h041,
        CSR_UCAUSE       = 12'h042,
        CSR_UTVAL        = 12'h043,
        CSR_UIP          = 12'h044,

        //--------------------------------------------------------
        // USER FLOATING POINT CSRs
        //--------------------------------------------------------

        CSR_FFLAGS       = 12'h001,
        CSR_FRM          = 12'h002,
        CSR_FCSR         = 12'h003,

        //--------------------------------------------------------
        // SUPERVISOR CSRs
        //--------------------------------------------------------

        CSR_SSTATUS      = 12'h100,
        CSR_SEDELEG      = 12'h102,
        CSR_SIDELEG      = 12'h103,
        CSR_SIE          = 12'h104,
        CSR_STVEC        = 12'h105,
        CSR_SCOUNTEREN   = 12'h106,

        CSR_SSCRATCH     = 12'h140,
        CSR_SEPC         = 12'h141,
        CSR_SCAUSE       = 12'h142,
        CSR_STVAL        = 12'h143,
        CSR_SIP          = 12'h144,

        CSR_SATP         = 12'h180,

        //--------------------------------------------------------
        // MACHINE INFORMATION REGISTERS
        //--------------------------------------------------------

        CSR_MVENDORID    = 12'hF11,
        CSR_MARCHID      = 12'hF12,
        CSR_MIMPID       = 12'hF13,
        CSR_MHARTID      = 12'hF14,

        //--------------------------------------------------------
        // MACHINE TRAP SETUP
        //--------------------------------------------------------

        CSR_MSTATUS      = 12'h300,
        CSR_MISA         = 12'h301,
        CSR_MEDELEG      = 12'h302,
        CSR_MIDELEG      = 12'h303,
        CSR_MIE          = 12'h304,
        CSR_MTVEC        = 12'h305,
        CSR_MCOUNTEREN   = 12'h306,

        //--------------------------------------------------------
        // MACHINE TRAP HANDLING
        //--------------------------------------------------------

        CSR_MSCRATCH     = 12'h340,
        CSR_MEPC         = 12'h341,
        CSR_MCAUSE       = 12'h342,
        CSR_MTVAL        = 12'h343,
        CSR_MIP          = 12'h344,

        //--------------------------------------------------------
        // MACHINE MEMORY PROTECTION (PMP)
        //--------------------------------------------------------

        CSR_PMPCFG0      = 12'h3A0,
        CSR_PMPCFG1      = 12'h3A1,
        CSR_PMPCFG2      = 12'h3A2,
        CSR_PMPCFG3      = 12'h3A3,

        CSR_PMPADDR0     = 12'h3B0,
        CSR_PMPADDR1     = 12'h3B1,
        CSR_PMPADDR2     = 12'h3B2,
        CSR_PMPADDR3     = 12'h3B3,
        CSR_PMPADDR4     = 12'h3B4,
        CSR_PMPADDR5     = 12'h3B5,
        CSR_PMPADDR6     = 12'h3B6,
        CSR_PMPADDR7     = 12'h3B7,
        CSR_PMPADDR8     = 12'h3B8,
        CSR_PMPADDR9     = 12'h3B9,
        CSR_PMPADDR10    = 12'h3BA,
        CSR_PMPADDR11    = 12'h3BB,
        CSR_PMPADDR12    = 12'h3BC,
        CSR_PMPADDR13    = 12'h3BD,
        CSR_PMPADDR14    = 12'h3BE,
        CSR_PMPADDR15    = 12'h3BF

    } csr_addr_t;

    //============================================================
    // EXCEPTION CAUSES (mcause / scause)
    //============================================================
    // XLEN-bit mcause:
    //   [XLEN-1] = interrupt flag
    //   [XLEN-2:0] = exception code
    //============================================================

    typedef enum logic [4:0] {

        //--------------------------------------------------------
        // Instruction-related exceptions
        //--------------------------------------------------------

        CAUSE_INSTR_ADDR_MISALIGN  = 5'd0,
        CAUSE_INSTR_ACCESS_FAULT   = 5'd1,
        CAUSE_ILLEGAL_INSTRUCTION  = 5'd2,

        //--------------------------------------------------------
        // Breakpoints / traps
        //--------------------------------------------------------

        CAUSE_BREAKPOINT           = 5'd3,

        //--------------------------------------------------------
        // Load / Store exceptions
        //--------------------------------------------------------

        CAUSE_LOAD_ADDR_MISALIGN   = 5'd4,
        CAUSE_LOAD_ACCESS_FAULT    = 5'd5,
        CAUSE_STORE_ADDR_MISALIGN  = 5'd6,
        CAUSE_STORE_ACCESS_FAULT   = 5'd7,

        //--------------------------------------------------------
        // Environment call
        //--------------------------------------------------------

        CAUSE_ECALL_U              = 5'd8,
        CAUSE_ECALL_S              = 5'd9,
        CAUSE_ECALL_M              = 5'd11,

        //--------------------------------------------------------
        // Page faults (if MMU enabled)
        //--------------------------------------------------------

        CAUSE_INSTR_PAGE_FAULT     = 5'd12,
        CAUSE_LOAD_PAGE_FAULT      = 5'd13,
        CAUSE_STORE_PAGE_FAULT     = 5'd15

    } exception_cause_t;

    //============================================================
    // INTERRUPT CAUSES (mcause MSB = 1)
    //============================================================

    typedef enum logic [XLEN-2:0] {

        // Software interrupts
        IRQ_U_SOFT     = (1 << 0),
        IRQ_S_SOFT     = (1 << 1),
        IRQ_M_SOFT     = (1 << 3),

        // Timer interrupts
        IRQ_U_TIMER    = (1 << 4),
        IRQ_S_TIMER    = (1 << 5),
        IRQ_M_TIMER    = (1 << 7),

        // External interrupts
        IRQ_U_EXT      = (1 << 8),
        IRQ_S_EXT      = (1 << 9),
        IRQ_M_EXT      = (1 << 11)

    } interrupt_cause_t;

    //============================================================
    // MSTATUS BIT POSITIONS (RV64)
    //============================================================

    typedef enum int {

        MSTATUS_UIE    = 0,
        MSTATUS_SIE    = 1,
        MSTATUS_MIE    = 3,

        MSTATUS_UPIE   = 4,
        MSTATUS_SPIE   = 5,
        MSTATUS_MPIE   = 7,

        MSTATUS_SPP    = 8,
        MSTATUS_MPP_L  = 11,   // MPP[1:0] = [11:12] (RV64 uses 2 bits)

        MSTATUS_FS_L   = 13,   // floating-point status
        MSTATUS_XS_L   = 15,

        MSTATUS_MPRV   = 17,

        MSTATUS_SUM    = 18,
        MSTATUS_MXR    = 19,

        MSTATUS_TVM    = 20,
        MSTATUS_TW     = 21,
        MSTATUS_TSR    = 22,

        MSTATUS_UXL_L  = 32,   // XLEN encoding (RV64)
        MSTATUS_SXL_L  = 34

    } mstatus_bits_t;

    //============================================================
    // SSTATUS BIT POSITIONS (subset of mstatus)
    //============================================================

    typedef enum int {

        SSTATUS_UIE   = 0,
        SSTATUS_SIE   = 1,

        SSTATUS_UPIE  = 4,
        SSTATUS_SPIE  = 5,

        SSTATUS_SPP   = 8,

        SSTATUS_FS_L  = 13,
        SSTATUS_XS_L  = 15,

        SSTATUS_SUM   = 18,
        SSTATUS_MXR   = 19

    } sstatus_bits_t;

    //============================================================
    // MIE / MIP BIT POSITIONS
    //============================================================

    typedef enum int {

        // Software interrupts
        MIE_MSIE = 3,
        MIE_SSIE = 1,
        MIE_USIE = 0,

        // Timer interrupts
        MIE_MTIE = 7,
        MIE_STIE = 5,
        MIE_UTIE = 4,

        // External interrupts
        MIE_MEIE = 11,
        MIE_SEIE = 9,
        MIE_UEIE = 8

    } mie_bits_t;

    typedef enum int {

        MIP_MSIP = 3,
        MIP_SSIP = 1,
        MIP_USIP = 0,

        MIP_MTIP = 7,
        MIP_STIP = 5,
        MIP_UTIP = 4,

        MIP_MEIP = 11,
        MIP_SEIP = 9,
        MIP_UEIP = 8

    } mip_bits_t;

    //============================================================
    // SATP (Address Translation Mode)
    //============================================================
    // RV64 SATP layout:
    //
    // [63:60] MODE
    // [59:44] ASID
    // [43:0]  PPN
    //============================================================

    typedef enum int {

        SATP_MODE_L     = 60,
        SATP_ASID_L     = 44,
        SATP_PPN_L      = 0

    } satp_bits_t;

    // Common SATP modes
    typedef enum logic [3:0] {

        SATP_MODE_BARE  = 4'd0,
        SATP_MODE_SV39  = 4'd8,
        SATP_MODE_SV48  = 4'd9,
        SATP_MODE_SV57  = 4'd10

    } satp_mode_t;

        //============================================================
    // INSTRUCTION FORMATS (32-bit base ISA)
    //============================================================

    typedef union packed {

        logic [31:0] word;

        //========================================================
        // R-TYPE
        // OP, OP-32, OP (M extension)
        //========================================================
        struct packed {
            logic [6:0]  funct7;
            logic [4:0]  rs2;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  rd;
            opcode_t     opcode;
        } r_type;

        //========================================================
        // I-TYPE
        //
        // LOAD
        // OP-IMM
        // OP-IMM-32
        // JALR
        // SYSTEM (CSR + ECALL/EBREAK)
        //========================================================
        struct packed {
            logic [11:0] imm;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  rd;
            opcode_t     opcode;
        } i_type;

        //========================================================
        // S-TYPE
        //
        // STORE
        //========================================================
        struct packed {
            logic [6:0]  imm11_5;
            logic [4:0]  rs2;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  imm4_0;
            opcode_t     opcode;
        } s_type;

        //========================================================
        // B-TYPE
        //
        // BRANCH
        //========================================================
        struct packed {
            logic       imm12;
            logic [5:0] imm10_5;
            logic [4:0] rs2;
            logic [4:0] rs1;
            logic [2:0] funct3;
            logic [3:0] imm4_1;
            logic       imm11;
            opcode_t    opcode;
        } b_type;

        //========================================================
        // U-TYPE
        //
        // LUI, AUIPC
        //========================================================
        struct packed {
            logic [19:0] imm;
            logic [4:0]  rd;
            opcode_t     opcode;
        } u_type;

        //========================================================
        // J-TYPE
        //
        // JAL
        //========================================================
        struct packed {
            logic        imm20;
            logic [9:0]  imm10_1;
            logic        imm11;
            logic [7:0]  imm19_12;
            logic [4:0]  rd;
            opcode_t    opcode;
        } j_type;

        //========================================================
        // AMO / LR / SC
        //========================================================
        struct packed {
            logic [4:0]  funct5;
            logic        aq;
            logic        rl;
            logic [4:0]  rs2;
            logic [4:0]  rs1;
            logic [2:0]  funct3;
            logic [4:0]  rd;
            opcode_t     opcode;
        } amo_type;

    } instr_t;

    //============================================================
    // COMPRESSED INSTRUCTION FORMAT (RV32C / RV64C)
    //============================================================

    typedef union packed {

        logic [15:0] halfword;

        struct packed {
            logic [1:0]  quadrant;
            logic [2:0]  opcode;
            logic [2:0]  funct3;
            logic [7:0]  payload;
        } c_type;

    } cinstr_t;

    //============================================================
    // PACKAGE END
    //============================================================

endpackage : riscv_types
