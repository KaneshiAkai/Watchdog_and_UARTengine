`timescale 1ns / 1ps

module tb_uart_system;

    // =========================================================
    // 1. KHAI BÁO TÍN HIỆU
    // =========================================================
    reg clk;
    reg B_s1;
    reg B_s2;
    reg uart_rx;
    
    wire uart_tx;
    wire wdo;
    wire en_o;

    // =========================================================
    // 2. THÔNG SỐ TIMING (27MHz & 115200 bps)
    // =========================================================
    // Clock 27MHz -> Chu kỳ ~ 37.037 ns. Dùng 37 ns cho mô phỏng
    parameter CLK_PERIOD = 37; 
    
    // Baudrate 115200 -> 1 bit = 1_000_000_000 / 115200 = 8680.5 ns
    parameter BIT_TIME = 8680; 

    // =========================================================
    // 3. KHỞI TẠO TOP MODULE (DUT)
    // =========================================================
    wd_top_module dut (
        .clk(clk),
        .B_s1(B_s1),
        .B_s2(B_s2),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .wdo(wdo),
        .en_o(en_o)
    );

    // =========================================================
    // 4. TẠO CLOCK 
    // =========================================================
    initial clk = 0;
    always #(CLK_PERIOD/2.0) clk = ~clk;

    // =========================================================
    // 5. CÁC TASK MÔ PHỎNG UART (HOST PC)
    // =========================================================
    
    // Task 1: Gửi 1 byte vật lý qua dây uart_rx
    task send_byte(input [7:0] tx_byte);
        integer i;
        begin
            uart_rx = 1'b0; // Start bit
            #(BIT_TIME);
            for (i=0; i<8; i=i+1) begin
                uart_rx = tx_byte[i]; // Data bits (LSB first)
                #(BIT_TIME);
            end
            uart_rx = 1'b1; // Stop bit
            #(BIT_TIME);
            #(BIT_TIME); // Nghỉ 1 nhịp giữa các byte
        end
    endtask

    // Task 2: Tự động tính Checksum và gửi nguyên khung lệnh
    task send_frame(
        input [7:0] cmd, 
        input [7:0] addr, 
        input [7:0] len, 
        input [31:0] data
    );
        reg [7:0] chk;
        begin
            // Thuật toán XOR Checksum (Tính lũy tiến)
            chk = cmd ^ addr ^ len;
            if (len == 4) begin
                chk = chk ^ data[31:24] ^ data[23:16] ^ data[15:8] ^ data[7:0];
            end else if (len == 2) begin
                chk = chk ^ data[15:8] ^ data[7:0];
            end
            
            $display("[Time %0t] HOST: Đang gửi lệnh CMD=%h, ADDR=%h, LEN=%h", $time, cmd, addr, len);
            
            // Truyền lần lượt
            send_byte(8'h55); // Sync Byte
            send_byte(cmd);
            send_byte(addr);
            send_byte(len);
            
            // Truyền Data theo chuẩn Big-Endian (Phù hợp với data_buf = (data_buf << 8) + rx_data của bạn)
            if (len == 4) begin
                send_byte(data[31:24]);
                send_byte(data[23:16]);
                send_byte(data[15:8]);
                send_byte(data[7:0]);
            end else if (len == 2) begin
                send_byte(data[15:8]);
                send_byte(data[7:0]);
            end
            
            send_byte(chk); // Byte kiểm tra lỗi
        end
    endtask

    // =========================================================
    // 6. KỊCH BẢN KIỂM CHỨNG (TEST SCENARIO)
    // =========================================================
    initial begin
        // Khởi tạo trạng thái an toàn
        uart_rx = 1'b1; // Idle UART state
        B_s1 = 1'b1;    // Nút nhấn chưa bấm (Pull-up)
        B_s2 = 1'b1;    // Nút nhấn chưa bấm (Pull-up)

        $display("------------------------------------------------------------");
        $display("[Time %0t] Đang chờ Internal Reset hoàn tất (~2.45 ms)...", $time);
        $display("------------------------------------------------------------");
        
        // Đợi 2.5 mili-giây để internal_rst đếm xong 16'hFFFF
        #2500000; 
        
        $display("[Time %0t] Reset hoàn tất. Bắt đầu truyền lệnh UART.", $time);

        // -----------------------------------------------------------------
        // SCENARIO 1: Ghi vào thanh ghi CTRL (0x00)
        // Mục đích: Bật en_sw = 1 và wdi_src = 1 (Dùng Software Kick)
        // -----------------------------------------------------------------
        // Data = 0x0000_0003 (bit 0 = 1, bit 1 = 1)
        send_frame(8'h01, 8'h00, 8'h04, 32'h00000003);
        
        // Đợi SoC xử lý và gửi phản hồi ECHO lên dây TX
        #500000; 

        // -----------------------------------------------------------------
        // SCENARIO 2: Ghi vào thanh ghi TWD_MS (0x04)
        // Mục đích: Chỉnh thời gian Watchdog timeout (VD: 500ms = 0x000001F4)
        // -----------------------------------------------------------------
        send_frame(8'h01, 8'h04, 8'h04, 32'h000001F4);
        #500000;

        // -----------------------------------------------------------------
        // SCENARIO 3: Đọc lại thanh ghi TWD_MS (0x04)
        // Mục đích: Xác nhận dữ liệu đã lưu vào Regfile thành công chưa
        // -----------------------------------------------------------------
        // Data phần đọc để bằng 0 vì module Parser không quan tâm Data khi là lệnh READ
        send_frame(8'h02, 8'h04, 8'h00, 32'h00000000);
        #500000;

        // -----------------------------------------------------------------
        // SCENARIO 4: Lệnh KICK Watchdog (0x03)
        // Mục đích: Test xung kick_en tạo ra từ Frame Parser
        // -----------------------------------------------------------------
        send_frame(8'h03, 8'h00, 8'h00, 32'h00000000);
        #500000;

        // -----------------------------------------------------------------
        // SCENARIO 5: Lệnh GET STATUS (0x04)
        // Mục đích: Đọc tổng hợp trạng thái WDO, ENOUT, FAULT
        // -----------------------------------------------------------------
        send_frame(8'h04, 8'h10, 8'h00, 32'h00000000);
        #500000;

        $display("------------------------------------------------------------");
        $display("[Time %0t] Testbench kết thúc. Vui lòng xem kết quả trên Waveform.", $time);
        $display("------------------------------------------------------------");
        
        // Dừng mô phỏng
        $finish;
    end

endmodule