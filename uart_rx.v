module uart_rx #(
    parameter integer OVERS      = 16,   // 비트당 샘플 횟수(오버샘플 비율)
    parameter integer DATA_BITS  = 8,    // UART 데이터 비트 수(표준 8)
    parameter         INVERT     = 0     // 1=입력 반전(필요할 때만)
)(
    input  wire clk,                     // 시스템 클럭(예: 100MHz)
    input  wire rst,                     // 동기 리셋
    input  wire tick,                    // baud_gen에서 온 오버샘플 틱(16회/비트)
    input  wire rx,                      // 외부 비동기 입력(옵토 출력 → FPGA 핀)
    output reg  vld,                     // 바이트 유효 신호(1클럭 펄스)
    output reg [7:0] data,               // 수신된 8비트 데이터
    output reg  framing_err              // Stop 비트가 0이면 1로 표시
);
    // ===== (1) 비동기 입력 동기화(2단 FF) =====
    reg rx_meta, rx_sync;
    always @(posedge clk) begin
        rx_meta <= rx;                   // 1단: 외부 → 내부 첫 샘플
        rx_sync <= rx_meta;              // 2단: 메타 안정성 개선
    end

    // ===== (2) 필요하면 폴라리티 반전 =====
    wire rx_s = INVERT ? ~rx_sync : rx_sync;

    // ===== (3) 상태 정의 =====
    localparam [2:0] ST_IDLE  = 3'd0,    // 유휴(라인=1 대기)
                     ST_START = 3'd1,    // Start 비트(0) 확인 단계
                     ST_DATA  = 3'd2,    // 데이터 8비트 수집
                     ST_STOP  = 3'd3;    // Stop 비트(1) 확인

    reg [2:0]  state;                    // 현재 상태
    reg [3:0]  os_cnt;                   // 오버샘플 카운터: 0..OVERS-1 (여기선 0..15)
    reg [2:0]  bit_idx;                  // 수집 중인 데이터 비트 인덱스: 0..7
    reg [7:0]  shreg;                    // 쉬프트 레지스터(LSB-first로 밀어넣음)

    // 비트 중앙 샘플 지점(16중 8번째 = MID)
    localparam integer MID = OVERS/2;

    always @(posedge clk) begin
        if (rst) begin
            // ===== (4) 리셋 시 전부 초기화 =====
            state       <= ST_IDLE;
            os_cnt      <= 0;
            bit_idx     <= 0;
            shreg       <= 0;
            data        <= 0;
            vld         <= 1'b0;
            framing_err <= 1'b0;

        end else begin
            vld <= 1'b0;                 // 기본값(1클럭 펄스이므로 매 싸이클 내려둠)

            if (tick) begin              // 오버샘플 틱마다만 상태를 한 스텝 진행
                case (state)

                // ===== (5) IDLE: Start 엣지 대기 =====
                ST_IDLE: begin
                    framing_err <= 1'b0; // 새 프레임 시작이므로 에러 플래그 클리어
                    if (rx_s == 1'b0) begin   // 유휴(1)에서 0 떨어지면 Start 후보
                        state  <= ST_START;
                        os_cnt <= 0;          // 이 비트의 오버샘플 카운터 초기화
                    end
                end

                // ===== (6) START: 중앙에서 다시 확인 =====
                ST_START: begin
                    os_cnt <= os_cnt + 1;     // 0,1,2,... tick 세기
                    if (os_cnt == MID-1) begin// MID 직전(=8번째 tick에서 검사)
                        if (rx_s == 1'b0) begin   // 진짜 Start(0)면
                            state   <= ST_DATA;   // 데이터 수집으로 진입
                            os_cnt  <= 0;         // 다음 비트용 카운터 리셋
                            bit_idx <= 0;         // 0번째 비트부터
                        end else begin
                            state  <= ST_IDLE;    // 글리치였음 → 원위치
                        end
                    end
                end

                // ===== (7) DATA: 8비트 수집(LSB→MSB) =====
                ST_DATA: begin
                    os_cnt <= os_cnt + 1;
                    if (os_cnt == MID-1) begin
                        // 비트 중앙에서 샘플해서 쉬프트
                        // LSB-first 규약: {새비트, 이전[7:1]}로 우측 쉬프트
                        shreg <= {rx_s, shreg[7:1]};
                    end
                    if (os_cnt == OVERS-1) begin
                        // 이 비트 기간 끝(=16번째 tick) → 다음 비트로
                        os_cnt <= 0;
                        if (bit_idx == DATA_BITS-1) begin
                            state <= ST_STOP;     // 8비트 완료 → Stop 검사
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end
                end

                // ===== (8) STOP: 중앙에서 1인지 체크 =====
                ST_STOP: begin
                    os_cnt <= os_cnt + 1;
                    if (os_cnt == MID-1) begin
                        // Stop 비트는 반드시 1이어야 정상 프레이밍
                        framing_err <= (rx_s == 1'b0);
                    end
                    if (os_cnt == OVERS-1) begin
                        // 프레임 종료 시점: 쉬프트값을 data로 확정
                        os_cnt <= 0;
                        data   <= shreg;
                        vld    <= ~framing_err;  // 정상일 때만 유효 펄스
                        state  <= ST_IDLE;       // 다음 바이트 대기
                    end
                end

                default: state <= ST_IDLE;
                endcase
            end // if (tick)
        end
    end
endmodule

