`timescale 1ns/1ps
module final_alu_recon_garner #(
    parameter integer WM = 5,
    parameter integer PW = 20
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire [3:0]           subset_id,
    input  wire [6*WM-1:0]      z_res_flat,
    input  wire [WM-1:0]        m0,
    input  wire [WM-1:0]        m1,
    input  wire [WM-1:0]        m2,
    input  wire [WM-1:0]        m3,
    input  wire [WM-1:0]        m4,
    input  wire [WM-1:0]        m5,
    output reg                  done,
    output reg  [PW-1:0]        subset_candidate
);

    function integer get_mod;
        input integer idx;
        begin
            case (idx)
                0: get_mod = m0;
                1: get_mod = m1;
                2: get_mod = m2;
                3: get_mod = m3;
                4: get_mod = m4;
                5: get_mod = m5;
                default: get_mod = 1;
            endcase
        end
    endfunction

    function integer get_res;
        input integer idx;
        begin
            case (idx)
                0: get_res = z_res_flat[(0*WM)+:WM];
                1: get_res = z_res_flat[(1*WM)+:WM];
                2: get_res = z_res_flat[(2*WM)+:WM];
                3: get_res = z_res_flat[(3*WM)+:WM];
                4: get_res = z_res_flat[(4*WM)+:WM];
                5: get_res = z_res_flat[(5*WM)+:WM];
                default: get_res = 0;
            endcase
        end
    endfunction

    task find_inv;
        input integer a;
        input integer m;
        output integer inv_out;
        integer aa;
        integer cand;
        begin
            inv_out = 0;
            if (m > 1) begin
                aa = a % m;
                if (aa < 0)
                    aa = aa + m;
                for (cand = 1; cand < 256; cand = cand + 1) begin
                    if ((((aa * cand) % m) == 1) && (inv_out == 0))
                        inv_out = cand;
                end
            end
        end
    endtask


    task decode_subset;
        input integer sid;
        output integer i0;
        output integer i1;
        output integer i2;
        output integer i3;
        begin
            case (sid)
                0:  begin i0=0; i1=1; i2=2; i3=3; end
                1:  begin i0=0; i1=1; i2=2; i3=4; end
                2:  begin i0=0; i1=1; i2=2; i3=5; end
                3:  begin i0=0; i1=1; i2=3; i3=4; end
                4:  begin i0=0; i1=1; i2=3; i3=5; end
                5:  begin i0=0; i1=1; i2=4; i3=5; end
                6:  begin i0=0; i1=2; i2=3; i3=4; end
                7:  begin i0=0; i1=2; i2=3; i3=5; end
                8:  begin i0=0; i1=2; i2=4; i3=5; end
                9:  begin i0=0; i1=3; i2=4; i3=5; end
                10: begin i0=1; i1=2; i2=3; i3=4; end
                11: begin i0=1; i1=2; i2=3; i3=5; end
                12: begin i0=1; i1=2; i2=4; i3=5; end
                13: begin i0=1; i1=3; i2=4; i3=5; end
                14: begin i0=2; i1=3; i2=4; i3=5; end
                default: begin i0=0; i1=1; i2=2; i3=3; end
            endcase
        end
    endtask

    integer i0;
    integer i1;
    integer i2;
    integer i3;
    integer mod0;
    integer mod1;
    integer mod2;
    integer mod3;
    integer res0;
    integer res1;
    integer res2;
    integer res3;
    integer m_all;
    integer mi;
    integer inv;
    integer acc;
    integer term;

    always @(posedge clk) begin
        if (!rst_n) begin
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            if (start) begin
                decode_subset(subset_id, i0, i1, i2, i3);
                mod0 = get_mod(i0); mod1 = get_mod(i1); mod2 = get_mod(i2); mod3 = get_mod(i3);
                res0 = get_res(i0); res1 = get_res(i1); res2 = get_res(i2); res3 = get_res(i3);
                m_all = mod0 * mod1 * mod2 * mod3;
                acc = 0;

                mi = m_all / mod0; find_inv(mi % mod0, mod0, inv); term = (((res0 % mod0) * (mi % m_all)) % m_all); term = (term * inv) % m_all; acc = (acc + term) % m_all;
                mi = m_all / mod1; find_inv(mi % mod1, mod1, inv); term = (((res1 % mod1) * (mi % m_all)) % m_all); term = (term * inv) % m_all; acc = (acc + term) % m_all;
                mi = m_all / mod2; find_inv(mi % mod2, mod2, inv); term = (((res2 % mod2) * (mi % m_all)) % m_all); term = (term * inv) % m_all; acc = (acc + term) % m_all;
                mi = m_all / mod3; find_inv(mi % mod3, mod3, inv); term = (((res3 % mod3) * (mi % m_all)) % m_all); term = (term * inv) % m_all; acc = (acc + term) % m_all;

                subset_candidate <= acc[PW-1:0];
                done             <= 1'b1;
            end
        end
    end

endmodule
