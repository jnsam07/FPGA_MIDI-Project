// 100 MHz 시스템 클럭 기준 (필요시 CLK_HZ만 바꿔 쓰세요)
module baud_gen #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 31_250,
    parameter integer OVERS  = 16
)(
    input  wire clk,
    input  wire rst,
    output reg  tick    // OVERS× 오버샘플링용 1클럭 펄스
);
    localparam integer DIV = CLK_HZ / (BAUD * OVERS); // 100e6/(31250*16)=200
    integer cnt;

    always @(posedge clk) begin
        if (rst) begin
            cnt  <= 0;
            tick <= 1'b0;
        end else begin
            if (cnt == DIV-1) begin
                cnt  <= 0;
                tick <= 1'b1;   // 한 클럭만 1
            end else begin
                cnt  <= cnt + 1;
                tick <= 1'b0;
            end
        end
    end
endmodule

