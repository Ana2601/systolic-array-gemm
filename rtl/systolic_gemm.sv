// INT8 GEMM accelerator built on an S x S output-stationary systolic array.
//
//   C[S][S] (int32) = A[S][K] (int8) x B[K][S] (int8),   1 <= K <= KMAX
//
// Flow:  write A and B into the on-chip operand buffers -> pulse `start` with
//        `k_len` -> wait for `done` -> read C through the result port.
// Row i of A enters from the left skewed by i cycles, column j of B from the
// top skewed by j cycles, so PE(i,j) sees A[i][k] and B[k][j] in the same
// cycle (k = t - i - j). A tile takes K + 2S - 2 compute cycles.
module systolic_gemm #(
    parameter integer S    = 8,
    parameter integer KMAX = 64
) (
    input  wire                     clk,
    input  wire                     rst_n,

    // operand buffer write port
    input  wire                     wr_en,
    input  wire                     wr_sel,     // 0: A[row][col]  1: B[row][col]
    input  wire [$clog2(KMAX)-1:0]  wr_row,
    input  wire [$clog2(KMAX)-1:0]  wr_col,
    input  wire signed [7:0]        wr_data,

    // control
    input  wire                     start,
    input  wire [$clog2(KMAX):0]    k_len,
    output reg                      busy,
    output reg                      done,       // one-cycle pulse
    output reg  [31:0]              cycles,     // compute cycles of the last tile

    // result read port (combinational)
    input  wire [$clog2(S)-1:0]     rd_row,
    input  wire [$clog2(S)-1:0]     rd_col,
    output wire signed [31:0]       rd_data
);
    localparam integer KW = $clog2(KMAX);

    reg signed [7:0] a_buf [0:S-1][0:KMAX-1];
    reg signed [7:0] b_buf [0:KMAX-1][0:S-1];

    always @(posedge clk)
        if (wr_en && !busy) begin
            if (!wr_sel) a_buf[wr_row[$clog2(S)-1:0]][wr_col] <= wr_data;
            else         b_buf[wr_row][wr_col[$clog2(S)-1:0]] <= wr_data;
        end

    // ------------------------------------------------------------ sequencing
    reg  [KW+1:0] t;
    reg  [KW:0]   k_q;
    reg           clear;
    wire [KW+1:0] t_last = {1'b0, k_q} + (KW+2)'(2 * S - 3);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0; done <= 1'b0; t <= 0; k_q <= 0; clear <= 1'b0; cycles <= 32'd0;
        end else begin
            done  <= 1'b0;
            clear <= 1'b0;
            if (!busy && start) begin
                busy <= 1'b1; k_q <= k_len; t <= 0; clear <= 1'b1; cycles <= 32'd0;
            end else if (busy && !clear) begin
                t      <= t + 1'b1;
                cycles <= cycles + 1;
                if (t == t_last) begin busy <= 1'b0; done <= 1'b1; end
            end
        end
    end

    wire run = busy && !clear;

    // ------------------------------------------------------------ skewed edge feeds
    wire signed [7:0] edge_a [0:S-1];
    wire signed [7:0] edge_b [0:S-1];
    genvar i, j;
    // t >= 0 is trivially true for row/column 0
    /* verilator lint_off UNSIGNED */
    generate
        for (i = 0; i < S; i = i + 1) begin : g_edge
            wire [KW+1:0] ka = t - (KW+2)'(i);               // wraps negative -> large -> out of range
            assign edge_a[i] = (run && t >= (KW+2)'(i) && ka < {1'b0, k_q}) ? a_buf[i][ka[KW-1:0]] : 8'sd0;
            assign edge_b[i] = (run && t >= (KW+2)'(i) && ka < {1'b0, k_q}) ? b_buf[ka[KW-1:0]][i] : 8'sd0;
        end
    endgenerate
    /* verilator lint_on UNSIGNED */

    // ------------------------------------------------------------ PE array
    wire signed [7:0]  a_w   [0:S-1][0:S-1];
    wire signed [7:0]  b_w   [0:S-1][0:S-1];
    wire signed [31:0] acc_w [0:S-1][0:S-1];

    generate
        for (i = 0; i < S; i = i + 1) begin : g_row
            for (j = 0; j < S; j = j + 1) begin : g_col
                systolic_pe u_pe (
                    .clk(clk), .clear(clear), .en(run),
                    .a_in ((j == 0) ? edge_a[i] : a_w[i][j-1]),
                    .b_in ((i == 0) ? edge_b[j] : b_w[i-1][j]),
                    .a_out(a_w[i][j]), .b_out(b_w[i][j]), .acc(acc_w[i][j])
                );
            end
        end
    endgenerate

    assign rd_data = acc_w[rd_row][rd_col];
endmodule
