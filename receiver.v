module receiver(
    input clk,
    input rst_n,
    input rdy_clr,      // 1 = clear rdy (busy), 0 = ready (idle)
    input clk_en,
    input rx,

    output reg rdy,
    output reg [7:0] data_out
);  

    parameter [2:0] S_START = 3'd0;
    parameter [2:0] S_DATA  = 3'd1;
    parameter [2:0] S_STOP  = 3'd2;

    reg [4:0] sample = 5'd0; 
    reg [1:0] state = 0;
    reg [3:0] index = 0;
    reg [7:0] temp_reg = 8'd0;

    reg rx_reg1, rx_reg2;
    always @(posedge clk) begin
        rx_reg1 <= rx;
        rx_reg2 <= rx_reg1;
    end
    // Sử dụng rx_reg2 cho toàn bộ logic thay vì rx trực tiếp

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rdy <= 1'b0;
            data_out <= 8'd0;
        end
        else begin
            if (clk_en) begin
                case (state)
                    S_START: begin
                        if (rdy_clr) begin
                            rdy <= 1'b0;      // clear rdy when busy
                        end

                        if (rx_reg2 == 0 || sample != 5'd0) begin
                            sample <= sample + 5'd1;
                        end

                        if (sample == 5'd15) begin
                            state <= S_DATA;
                            sample <= 5'd0;
                            index <= 4'd0;
                            temp_reg <= 8'd0;
                        end
                    end

                    S_DATA: begin
                        if (sample == 5'd15) begin              // Còn một phương pháp khác tiết kiệm memory hơn
                            sample <= 5'd0;                     // Khai báo sample chỉ 4 bit
                        end                                     // thì khi sample đạt 15 (tức là đã đủ 16 lần xung nhịp), reset về 0 và tăng index
                        else begin                            
                            sample <= sample + 5'd1;            // Cách này sẽ tiết kiệm được 1 bit memory cho sample
                        end
                        if (sample == 5'd8) begin
                            temp_reg[index] <= rx_reg2;
                            index <= index + 4'd1;
                        end
                        if (index == 4'd8 && sample == 5'd15) begin
                            state <= S_STOP;
                        end
                    end

                    S_STOP: begin
                        if (sample == 5'd15) begin
                            state <= S_START;
                            sample <= 5'd0;
                            data_out <= temp_reg;
                            rdy <= 1'b1;      // set rdy when data is ready  // Announce a new data for parser to read
                        end
                        else begin
                            sample <= sample + 5'd1;
                        end
                    end

                    default: begin
                        state <= S_START;
                    end
                endcase
            end
        end
    end

endmodule