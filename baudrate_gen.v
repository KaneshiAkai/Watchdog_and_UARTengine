    module baudrate_gen #(
        parameter CLK_FREQ_HZ = 27_000_000,
        parameter BAUD_RATE   = 115200
    )(
        input  wire clk,
        output wire rx_en,
        output wire tx_en
    );

        // 1. BÍ QUYẾT LÀM TRÒN SỐ (HARDWARE ROUNDING TRICK)
        // Công thức (Clock + Target/2) / Target giúp làm tròn đến số nguyên gần nhất thay vì cắt cụt.
        
        localparam RX_TICK_RATE = BAUD_RATE * 16;
        
        // Số chu kỳ đếm cho RX (Oversampling 16x)
        // (27M + 1.8432M/2) / 1.8432M = 14.648... -> Làm tròn thành 15
        // Trong baudrate_gen.v
        localparam CYCLES_PER_RX = CLK_FREQ_HZ / (BAUD_RATE * 16); // 27M / (115200*16) = 14.64 -> lấy 14 hoặc 15
        localparam CYCLES_PER_TX = CYCLES_PER_RX * 16;            // Đảm bảo TX gấp đúng 16 lần RX
        
        // Số chu kỳ đếm cho TX (1x)
        // (27M + 115200/2) / 115200 = 234.375... -> Làm tròn thành 234  

        // 2. Tự động tính số bit tối ưu cho thanh ghi (Auto-calculate register width)
        reg [$clog2(CYCLES_PER_RX)-1:0] cnt_rx = 0;
        reg [$clog2(CYCLES_PER_TX)-1:0] cnt_tx = 0;

        // 3. Logic Bộ đếm RX (RX Counter Logic)
        always @(posedge clk) begin
            // Để đếm đủ N chu kỳ, phải reset khi đạt N - 1
            if (cnt_rx >= (CYCLES_PER_RX - 1)) begin 
                cnt_rx <= 0;
            end else begin
                cnt_rx <= cnt_rx + 1'b1;
            end
        end
        
        // Tạo xung rx_en chỉ kéo dài đúng 1 chu kỳ clock hệ thống
        assign rx_en = (cnt_rx == 0);

        // 4. Logic Bộ đếm TX (TX Counter Logic)
        always @(posedge clk) begin
            // Để đếm đủ N chu kỳ, phải reset khi đạt N - 1
            if (cnt_tx >= (CYCLES_PER_TX - 1)) begin
                cnt_tx <= 0;
            end else begin
                cnt_tx <= cnt_tx + 1'b1;
            end
        end
        
        // Tạo xung tx_en chỉ kéo dài đúng 1 chu kỳ clock hệ thống
        assign tx_en = (cnt_tx == 0);

    endmodule