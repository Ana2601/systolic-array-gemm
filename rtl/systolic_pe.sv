// Output-stationary processing element: acc += a * b, then pass a right and b down.
module systolic_pe (
    input  wire               clk,
    input  wire               clear,     // synchronous accumulator clear
    input  wire               en,
    input  wire signed [7:0]  a_in,
    input  wire signed [7:0]  b_in,
    output reg  signed [7:0]  a_out,
    output reg  signed [7:0]  b_out,
    output reg  signed [31:0] acc
);
    always @(posedge clk) begin
        if (clear) begin
            acc <= 32'sd0; a_out <= 8'sd0; b_out <= 8'sd0;
        end else if (en) begin
            acc   <= acc + a_in * b_in;
            a_out <= a_in;
            b_out <= b_in;
        end
    end
endmodule
