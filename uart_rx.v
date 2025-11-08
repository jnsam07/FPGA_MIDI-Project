module uart_rx #(
    parameter integer OVERS      = 16,   // 오버샘플 비율
    parameter integer DATA_BITS  = 8,
    parameter         INVERT     = 0     // 1이면 입력 반전
)(
    input  wire clk,
    input  wire rst,
    input  wire tick,           // baud_gen에서 생성한 오버샘플 tick
    input  wire rx,             // 비동기 입력 (옵토 출력 → FPGA 핀)
    output reg  vld,            // 수신 바이트 유효 1클럭 펄스
    output reg [7:0] data,      // 수신 데이터
    output reg  framing_err     // Stop 비트 오류
);
    // 비동기 입력 동기화 (메타 안정성 방지)
    reg rx_meta, rx_sync;
    always @(posedge clk) begin
        rx_meta <= rx;
        rx_sync <= rx_meta;
    end

    wire rx_s = INVERT ? ~rx_sync : rx_sync;

    localparam [2:0] ST_IDLE  = 3'd0,
                     ST_START = 3'd1,
                     ST_DATA  = 3'd2,
                     ST_STOP  = 3'd3;

    reg [2:0]  state;
    reg [3:0]  os_cnt;                // 0..OVERS-1
    reg [2:0]  bit_idx;               // 0..(DATA_BITS-1)
    reg [7:0]  shreg;

    // 중앙 샘플 위치: OVERS/2 (=8) 지점
    localparam integer MID = OVERS/2;

    always @(posedge clk) begin
        if (rst) begin
            state       <= ST_IDLE;
            os_cnt      <= 0;
            bit_idx     <= 0;
            shreg       <= 0;
            data        <= 0;
            vld         <= 1'b0;
            framing_err <= 1'b0;
        end else begin
            vld         <= 1'b0;

            if (tick) begin
                case (state)
                    ST_IDLE: begin
                        framing_err <= 1'b0;
                        // Start 비트 감지: Idle=1에서 0으로 떨어짐
                        if (rx_s == 1'b0) begin
                            state  <= ST_START;
                            os_cnt <= 0;
                        end
                    end

                    ST_START: begin
                        os_cnt <= os_cnt + 1;
                        // Start 비트 중앙에서 재확인
                        if (os_cnt == MID-1) begin
                            if (rx_s == 1'b0) begin
                                state   <= ST_DATA;
                                os_cnt  <= 0;
                                bit_idx <= 0;
                            end else begin
                                // 글리치였음 → 복귀
                                state  <= ST_IDLE;
                            end
                        end
                    end

                    ST_DATA: begin
                        os_cnt <= os_cnt + 1;
                        if (os_cnt == MID-1) begin
                            // 중앙 샘플링해서 LSB-first로 shift-in
                            shreg <= {rx_s, shreg[7:1]};
                        end
                        if (os_cnt == OVERS-1) begin
                            os_cnt <= 0;
                            if (bit_idx == DATA_BITS-1) begin
                                state   <= ST_STOP;
                            end else begin
                                bit_idx <= bit_idx + 1;
                            end
                        end
                    end

                    ST_STOP: begin
                        os_cnt <= os_cnt + 1;
                        if (os_cnt == MID-1) begin
                            // Stop 비트는 1이어야 함
                            framing_err <= (rx_s == 1'b0);
                        end
                        if (os_cnt == OVERS-1) begin
                            os_cnt <= 0;
                            data   <= shreg;
                            vld    <= ~framing_err; // 정상일 때만 vld=1
                            state  <= ST_IDLE;
                        end
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end
endmodule
