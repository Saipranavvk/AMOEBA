#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/types.h>

// Shadow register files (committed state)
static uint64_t s_iregs[32];
static uint64_t s_fregs[32];
static FILE    *s_pipe;
static char     s_next_line[512];
static int      s_has_next;
static int      s_pipe_dead;  // set when pipe is NULL or hits EOF without any commits
// Program base address parsed from mem_space (e.g. "0x80000000" from "-m0x80000000:...")
// Boot ROM lines (PC < s_prog_base) are skipped so Spike stays in sync with the DUT.
static uint64_t s_prog_base;
static int s_spike_exit_code = -1;  // Exit status of Spike process: 0=clean, 1=error, -1=unknown
static pid_t s_spike_pid = -1;  // Spike process ID for kill/waitpid

// WData helpers: 35-word array, word[0]=LSB field (mem_wdata[31:0]), word[34]=MSB field (inst)
static inline void w64(uint32_t *r, int lo, uint64_t v) {
    r[lo]     = (uint32_t)(v & 0xFFFFFFFFu);
    r[lo + 1] = (uint32_t)(v >> 32);
}
static inline void w32(uint32_t *r, int i, uint32_t v) {
    r[i] = v;
}

// Matches monitor.sv's funct3_to_mask: byte enables from funct3[1:0] and byte offset
static uint8_t mem_mask(uint32_t funct3, uint32_t offset) {
    switch (funct3 & 3u) {
        case 0:  return (uint8_t)(0x01u << offset);
        case 1:  return (uint8_t)(0x03u << (offset & ~1u));
        case 2:  return (uint8_t)(0x0Fu << (offset & ~3u));
        default: return 0xFFu;
    }
}

extern "C" void spike_dpi_init(const char *mem_space, const char *elf_file) {
    memset(s_iregs, 0, sizeof(s_iregs));
    memset(s_fregs, 0, sizeof(s_fregs));
    s_has_next  = 0;
    s_pipe_dead = 0;
    s_next_line[0] = '\0';

    // Parse base address from "-m0x<base>:<size>" so we can skip Spike's boot ROM
    s_prog_base = 0;
    const char *p = mem_space;
    while (*p) {
        if (*p == 'm' && *(p+1) == '0' && *(p+2) == 'x') {
            s_prog_base = (uint64_t)strtoull(p + 1, NULL, 16);
            break;
        }
        ++p;
    }

    // Use locally built spike (with --log-commits support) if system spike lacks it.
    // Falls back to "spike" in PATH if local build doesn't exist.
    char spike_bin[256];
    const char *local = "/tmp/spike-build/riscv-isa-sim/build/spike";
    if (access(local, X_OK) == 0)
        snprintf(spike_bin, sizeof(spike_bin), "%s", local);
    else
        snprintf(spike_bin, sizeof(spike_bin), "spike");

    char cmd[2048];
    snprintf(cmd, sizeof(cmd),
        "%s --isa=rv64gc_zicsr_zifencei %s --log-commits \"%s\" </dev/null 2>&1",
        spike_bin, mem_space, elf_file);

    int pipefd[2];
    pipe(pipefd);
    s_spike_pid = fork();
    if (s_spike_pid == 0) {
        int null_fd = open("/dev/null", O_RDONLY);
        if (null_fd >= 0) { dup2(null_fd, STDIN_FILENO); close(null_fd); }
        dup2(pipefd[1], STDOUT_FILENO);
        dup2(pipefd[1], STDERR_FILENO);
        close(pipefd[0]); close(pipefd[1]);
        execl("/bin/sh", "sh", "-c", cmd, (char*)NULL);
        _exit(1);
    }
    close(pipefd[1]);
    s_pipe = fdopen(pipefd[0], "r");
}

extern "C" unsigned int spike_dpi_fin() {
    if (s_pipe) {
        // Drain with select timeout.
        int fd = fileno(s_pipe);
        char drain[4096];
        for (int i = 0; i < 10; ++i) {
            fd_set rfds; FD_ZERO(&rfds); FD_SET(fd, &rfds);
            struct timeval tv = {1, 0};
            if (select(fd + 1, &rfds, NULL, NULL, &tv) <= 0) break;
            if (!FD_ISSET(fd, &rfds)) break;
            if (fread(drain, 1, sizeof(drain), s_pipe) == 0) break;
        }
        fclose(s_pipe);
        s_pipe = NULL;
    }
    // Force-terminate Spike if still running.
    if (s_spike_pid > 0) {
        kill(s_spike_pid, SIGTERM);
        for (int i = 0; i < 20; ++i) {
            usleep(100000);  // 100 ms
            int st;
            if (waitpid(s_spike_pid, &st, WNOHANG) == s_spike_pid) {
                if (s_spike_exit_code == -1)
                    s_spike_exit_code = (WIFEXITED(st) && WEXITSTATUS(st) == 0) ? 0 : 1;
                s_spike_pid = -1;
                break;
            }
        }
        if (s_spike_pid > 0) {
            kill(s_spike_pid, SIGKILL);
            waitpid(s_spike_pid, NULL, 0);
            s_spike_pid = -1;
        }
    }
    return 0;
}

extern "C" const char *spike_dpi_dasm() { return ""; }

// Force-write a value into Spike's shadow integer register file.  Used by
// monitor.sv to re-sync Spike's register state after a suppressed MMIO load
// mismatch (where Spike's device stub returned a different value than the DUT).
extern "C" void spike_dpi_set_ireg(uint32_t reg, uint64_t val) {
    if (reg > 0 && reg < 32)
        s_iregs[reg] = val;
}

// Called once per retired instruction; fills 35-word WData array r[].
// WData layout (last SV field = word[0]):
//   [0,1]=mem_wdata  [2,3]=mem_rdata  [4]=mem_wmask  [5]=mem_rmask
//   [6,7]=mem_addr   [8,9]=pc_wdata   [10,11]=pc_rdata
//   [12,13]=frd_wdata  [14]=frd_addr  [15,16]=frs3_rdata
//   [17,18]=frs2_rdata  [19,20]=frs1_rdata  [21]=frs3_addr
//   [22]=frs2_addr  [23]=frs1_addr  [24,25]=rd_wdata  [26]=rd_addr
//   [27,28]=rs2_rdata  [29,30]=rs1_rdata  [31]=rs2_addr  [32]=rs1_addr
//   [33]=trapped  [34]=inst
extern "C" unsigned int spike_dpi_next(uint32_t *r) {
    memset(r, 0, 35 * sizeof(uint32_t));
    if (s_pipe_dead) return (s_spike_exit_code == 0) ? 3 : 2;

    char     line[512];
    uint64_t cur_pc   = 0;
    uint32_t insn     = 0;
    int      got_insn = 0;
    // Collect per-instruction side effects
    int      int_reg  = -1;    // destination integer register (-1 = none)
    uint64_t int_val  = 0;
    int      fp_reg   = -1;    // destination FP register (-1 = none)
    uint64_t fp_val   = 0;
    uint64_t mem_raw  = 0;     // raw memory byte address
    int      has_mem  = 0;

    // Collect all log lines for one instruction (same PC)
    for (;;) {
        if (s_has_next) {
            memcpy(line, s_next_line, sizeof(line));
            s_has_next = 0;
        } else {
            // Wait up to 60s for Spike to produce a line.
            int fd = fileno(s_pipe);
            fd_set rfds; FD_ZERO(&rfds); FD_SET(fd, &rfds);
            struct timeval tv = {60, 0};
            if (select(fd + 1, &rfds, NULL, NULL, &tv) <= 0) {
                fprintf(stderr, "[SPIKE_DPI] Spike did not respond within 60s — killing\n");
                if (s_spike_pid > 0) { kill(s_spike_pid, SIGKILL); waitpid(s_spike_pid, NULL, 0); s_spike_pid = -1; }
                fclose(s_pipe); s_pipe = NULL; s_pipe_dead = 1;
                s_spike_exit_code = 1;  // treat as error
                if (!got_insn) return 2;
                break;
            }
            if (!fgets(line, sizeof(line), s_pipe)) {
                // EOF — Spike exited; collect exit status
                int status = 0;
                if (s_spike_pid > 0) { waitpid(s_spike_pid, &status, 0); s_spike_pid = -1; }
                fclose(s_pipe); s_pipe = NULL; s_pipe_dead = 1;
                s_spike_exit_code = (WIFEXITED(status) && WEXITSTATUS(status) == 0) ? 0 : 1;
                break;
            }
        }
        if (strncmp(line, "core", 4) != 0) continue;

        uint64_t pc; unsigned enc;
        if (sscanf(line, "core %*u: %*u 0x%lx (0x%x)", &pc, &enc) != 2) continue;

        // Skip Spike's internal boot ROM (PC below program base) — DUT doesn't commit these
        if (s_prog_base && pc < s_prog_base) continue;

        if (!got_insn) {
            cur_pc = pc; insn = (uint32_t)enc; got_insn = 1;
        } else {
            // Different PC = next instruction; same PC = next loop iteration (self-loop/tight loop).
            // Either way, stash as lookahead for pc_wdata and stop reading.
            memcpy(s_next_line, line, sizeof(s_next_line));
            s_has_next = 1;
            break;
        }

        // Parse side effect from the part after ")"
        const char *p = strchr(line, ')');
        if (!p) continue;
        ++p;
        while (*p == ' ') ++p;
        if (!*p || *p == '\n' || *p == '\r') continue;

        if (p[0] == 'x') {
            unsigned n; uint64_t v; int consumed = 0;
            if (sscanf(p + 1, "%u 0x%lx%n", &n, &v, &consumed) == 2 && n > 0 && n < 32) {
                int_reg = (int)n; int_val = v;
                // Loads: "x<n> 0x<val> mem 0x<addr>" all on same line
                const char *rest = p + 1 + consumed;
                while (*rest == ' ') ++rest;
                if (strncmp(rest, "mem", 3) == 0) { sscanf(rest + 4, "0x%lx", &mem_raw); has_mem = 1; }
            }
        } else if (p[0] == 'f' && p[1] >= '0' && p[1] <= '9') {
            unsigned n; uint64_t v; int consumed = 0;
            if (sscanf(p + 1, "%u 0x%lx%n", &n, &v, &consumed) == 2 && n < 32) {
                fp_reg = (int)n; fp_val = v;
                const char *rest = p + 1 + consumed;
                while (*rest == ' ') ++rest;
                if (strncmp(rest, "mem", 3) == 0) { sscanf(rest + 4, "0x%lx", &mem_raw); has_mem = 1; }
            }
        } else if (strncmp(p, "mem", 3) == 0) {
            sscanf(p + 4, "0x%lx", &mem_raw);
            has_mem = 1;
        }
    }

    if (!got_insn) {
        s_pipe_dead = 1;
        return (s_spike_exit_code == 0) ? 3 : 2;
    }

    // -------- decode RISC-V instruction fields --------
    uint32_t op        = insn & 0x7Fu;
    int      comp      = ((op & 3u) != 3u);    // 16-bit compressed
    uint32_t op5       = (op >> 2) & 0x1Fu;    // opcode[6:2]
    uint32_t i_rs1     = (insn >> 15) & 0x1Fu;
    uint32_t i_rs2     = (insn >> 20) & 0x1Fu;
    uint32_t i_rs3     = (insn >> 27) & 0x1Fu;
    uint32_t funct7h   = (insn >> 27) & 0x1Fu; // funct7[6:2] = bits[31:27]

    // Source register addresses (0 = not used → comparison skipped by monitor)
    uint32_t rs1_addr = 0, rs2_addr = 0;
    uint32_t frs1_addr = 0, frs2_addr = 0, frs3_addr = 0;

    if (!comp) {
        switch (op5) {
        case 0x0D: case 0x05: case 0x1B:               // LUI, AUIPC, JAL
            break;
        case 0x19: case 0x00: case 0x04: case 0x06:    // JALR, Load, I-ALU, I-ALU-32
        case 0x1C: case 0x03:                           // SYSTEM, MISC-MEM
            rs1_addr = i_rs1;
            break;
        case 0x18: case 0x08: case 0x0C: case 0x0E:    // Branch, Store, R-type, R32
        case 0x0B:                                      // AMO
            rs1_addr = i_rs1; rs2_addr = i_rs2;
            break;
        case 0x02:                                      // Load-FP: integer base
            rs1_addr = i_rs1;
            break;
        case 0x0A:                                      // Store-FP: integer base + FP src
            rs1_addr = i_rs1; frs2_addr = i_rs2;
            break;
        case 0x10: case 0x11: case 0x12: case 0x13:    // FMADD/FMSUB/FNMSUB/FNMADD
            frs1_addr = i_rs1; frs2_addr = i_rs2; frs3_addr = i_rs3;
            break;
        case 0x14:                                      // OP-FP
            switch (funct7h) {
            case 0x00: case 0x01: case 0x02: case 0x03:  // FADD, FSUB, FMUL, FDIV
            case 0x04:                                    // FSGNJ family
            case 0x05:                                    // FMIN, FMAX
            case 0x14:                                    // FCMP (FEQ, FLT, FLE) → int rd
                frs1_addr = i_rs1; frs2_addr = i_rs2;
                break;
            case 0x0B:                                    // FSQRT
            case 0x08:                                    // FCVT between FP formats
            case 0x18:                                    // FCVT.X.FP → int rd
            case 0x1C:                                    // FMV.X.W/D, FCLASS → int rd
                frs1_addr = i_rs1;
                break;
            case 0x1A:                                    // FCVT.FP.X: int rs1 → FP rd
            case 0x1E:                                    // FMV.FP.X: int rs1 → FP rd
                rs1_addr = i_rs1;
                break;
            default:
                frs1_addr = i_rs1;
                break;
            }
            break;
        default:
            rs1_addr = i_rs1; rs2_addr = i_rs2;
            break;
        }
    }
    // Compressed: leave all addr = 0 (skips comparison checks)

    // -------- snapshot shadow regs BEFORE updating --------
    uint64_t rs1_rd  = s_iregs[rs1_addr];
    uint64_t rs2_rd  = s_iregs[rs2_addr];
    uint64_t frs1_rd = s_fregs[frs1_addr];
    uint64_t frs2_rd = s_fregs[frs2_addr];
    uint64_t frs3_rd = s_fregs[frs3_addr];

    // -------- update shadow regs with this instruction's writes --------
    uint32_t rd_addr  = 0; uint64_t rd_wdata  = 0;
    uint32_t frd_addr = 0; uint64_t frd_wdata = 0;
    if (int_reg > 0) {
        s_iregs[(uint32_t)int_reg] = int_val;
        rd_addr  = (uint32_t)int_reg;
        rd_wdata = int_val;
    }
    if (fp_reg >= 0) {
        s_fregs[(uint32_t)fp_reg] = fp_val;
        frd_addr  = (uint32_t)fp_reg;
        frd_wdata = fp_val;
    }

    // -------- memory fields --------
    uint64_t m_addr  = 0; uint32_t m_rmask = 0, m_wmask = 0;
    uint64_t m_rdata = 0, m_wdata = 0;

    if (has_mem) {
        uint32_t offset = (uint32_t)(mem_raw & 7u);
        m_addr = mem_raw & ~7ULL;

        if (!comp) {
            uint32_t funct3 = (insn >> 12) & 0x7u;
            uint8_t bm = mem_mask(funct3, offset);
            if (op5 == 0x00) {                        // integer load
                m_rmask = bm; m_rdata = rd_wdata << (offset * 8u);
            } else if (op5 == 0x02) {                 // FP load
                m_rmask = bm; m_rdata = frd_wdata << (offset * 8u);
            } else if (op5 == 0x08) {                 // integer store
                m_wmask = bm; m_wdata = rs2_rd << (offset * 8u);
            } else if (op5 == 0x0A) {                 // FP store
                m_wmask = bm; m_wdata = frs2_rd << (offset * 8u);
            } else if (op5 == 0x0B) {                 // AMO
                m_rmask = bm; m_wmask = bm;
                m_rdata = rd_wdata << (offset * 8u);
            }
        } else {
            // Compressed memory instructions (Q0 = register-indirect, Q2 = SP-relative)
            uint32_t c_insn  = insn & 0xFFFFu;
            uint32_t q       = c_insn & 3u;
            uint32_t cf3     = (c_insn >> 13) & 7u;
            if (q == 0) {
                uint32_t c_rs2 = ((c_insn >> 2) & 7u) + 8u;  // CL/CS: rs2'/rd' in bits[4:2]
                switch (cf3) {
                case 1: m_rmask = 0xFFu; m_rdata = frd_wdata; break;                                     // C.FLD
                case 2: m_rmask = mem_mask(2,offset); m_rdata = rd_wdata << (offset*8u); break;           // C.LW
                case 3: m_rmask = 0xFFu; m_rdata = rd_wdata; break;                                      // C.LD
                case 5: m_wmask = 0xFFu; m_wdata = s_fregs[c_rs2]; break;                                // C.FSD
                case 6: m_wmask = mem_mask(2,offset); m_wdata = s_iregs[c_rs2] << (offset*8u); break;   // C.SW
                case 7: m_wmask = 0xFFu; m_wdata = s_iregs[c_rs2]; break;                                // C.SD
                }
            } else if (q == 2) {
                uint32_t c_rs2 = (c_insn >> 2) & 0x1Fu;      // CSS: rs2 in bits[6:2]
                switch (cf3) {
                case 1: m_rmask = 0xFFu; m_rdata = frd_wdata; break;                                     // C.FLDSP
                case 2: m_rmask = mem_mask(2,offset); m_rdata = rd_wdata << (offset*8u); break;           // C.LWSP
                case 3: m_rmask = 0xFFu; m_rdata = rd_wdata; break;                                      // C.LDSP
                case 5: m_wmask = 0xFFu; m_wdata = s_fregs[c_rs2]; break;                                // C.FSDSP
                case 6: m_wmask = mem_mask(2,offset); m_wdata = s_iregs[c_rs2] << (offset*8u); break;   // C.SWSP
                case 7: m_wmask = 0xFFu; m_wdata = s_iregs[c_rs2]; break;                                // C.SDSP
                }
            }
        }
    }

    // -------- pc_wdata: next PC from lookahead --------
    uint64_t pc_wdata_v = cur_pc + (comp ? 2u : 4u);
    if (s_has_next) {
        uint64_t npc; unsigned nenc;
        if (sscanf(s_next_line, "core %*u: %*u 0x%lx (0x%x)", &npc, &nenc) == 2)
            pc_wdata_v = npc;
    }

    // -------- fill 35-word WData array --------
    w64(r,  0, m_wdata);
    w64(r,  2, m_rdata);
    w32(r,  4, m_wmask);
    w32(r,  5, m_rmask);
    w64(r,  6, m_addr);
    w64(r,  8, pc_wdata_v);
    w64(r, 10, cur_pc);
    w64(r, 12, frd_wdata);
    w32(r, 14, frd_addr);
    w64(r, 15, frs3_rd);
    w64(r, 17, frs2_rd);
    w64(r, 19, frs1_rd);
    w32(r, 21, frs3_addr);
    w32(r, 22, frs2_addr);
    w32(r, 23, frs1_addr);
    w64(r, 24, rd_wdata);
    w32(r, 26, rd_addr);
    w64(r, 27, rs2_rd);
    w64(r, 29, rs1_rd);
    w32(r, 31, rs2_addr);
    w32(r, 32, rs1_addr);
    w32(r, 33, 0);           // trapped = 0 (normal retirement)
    w32(r, 34, insn);

    return 1;
}
