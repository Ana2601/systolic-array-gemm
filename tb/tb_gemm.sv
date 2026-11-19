`timescale 1ns/1ps
module tb_gemm;
    parameter integer S = 8, KMAX = 64;
    localparam integer KW = $clog2(KMAX), SW = $clog2(S);

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg                 wr_en = 0, wr_sel = 0, start = 0;
    reg  [KW-1:0]       wr_row = 0, wr_col = 0;
    reg  signed [7:0]   wr_data = 0;
    reg  [KW:0]         k_len = 0;
    reg  [SW-1:0]       rd_row = 0, rd_col = 0;
    wire                busy, done;
    wire [31:0]         cycles;
    wire signed [31:0]  rd_data;

    systolic_gemm #(.S(S), .KMAX(KMAX)) dut (.*);

    integer fd, r, k, i, j, tiles = 0, errors = 0;
    longint macs = 0, cyc_sum = 0;
    reg [7:0]  v8;
    reg [31:0] v32;
    reg [31:0] exp_c [0:S-1][0:S-1];
    string vec_file;

    initial begin
        if (!$value$plusargs("vectors=%s", vec_file)) vec_file = "build/vectors.txt";
        fd = $fopen(vec_file, "r");
        repeat (3) @(posedge clk);
        rst_n = 1;
        while (1) begin
            r = $fscanf(fd, "%h", k);
            if (r != 1) break;
            // load A and B
            for (i = 0; i < S; i = i + 1) for (j = 0; j < k; j = j + 1) begin
                r = $fscanf(fd, "%h", v8);
                wr_en <= 1; wr_sel <= 0; wr_row <= i; wr_col <= j; wr_data <= v8;
                @(posedge clk);
            end
            for (i = 0; i < k; i = i + 1) for (j = 0; j < S; j = j + 1) begin
                r = $fscanf(fd, "%h", v8);
                wr_en <= 1; wr_sel <= 1; wr_row <= i; wr_col <= j; wr_data <= v8;
                @(posedge clk);
            end
            wr_en <= 0;
            for (i = 0; i < S; i = i + 1) for (j = 0; j < S; j = j + 1) begin
                r = $fscanf(fd, "%h", v32); exp_c[i][j] = v32;
            end
            // compute
            k_len <= k; start <= 1;
            @(posedge clk); start <= 0;
            while (!done) @(posedge clk);
            if (cycles != k + 2 * S - 2) begin
                errors = errors + 1; $display("ERROR: K=%0d took %0d cycles, expected %0d", k, cycles, k + 2 * S - 2);
            end
            cyc_sum = cyc_sum + cycles;
            macs    = macs + S * S * k;
            // read back
            for (i = 0; i < S; i = i + 1) for (j = 0; j < S; j = j + 1) begin
                rd_row = i; rd_col = j; #1;
                if (rd_data !== $signed(exp_c[i][j])) begin
                    errors = errors + 1;
                    if (errors <= 10) $display("MISMATCH tile %0d K=%0d C[%0d][%0d]: got %0d exp %0d",
                                               tiles, k, i, j, rd_data, $signed(exp_c[i][j]));
                end
            end
            tiles = tiles + 1;
        end
        $display("GEMM %0dx%0d array: %0d tiles, %0d errors", S, S, tiles, errors);
        $display("  %0d MACs in %0d compute cycles -> %.1f MAC/cycle (peak %0d), PE utilisation %.1f%%",
                 macs, cyc_sum, 1.0 * macs / cyc_sum, S * S, 100.0 * macs / (cyc_sum * S * S));
        if (errors != 0 || tiles == 0) $fatal(1, "TEST FAILED");
        $display("TEST PASSED");
        $finish;
    end
endmodule
