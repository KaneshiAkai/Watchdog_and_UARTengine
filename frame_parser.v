module frame_parser (
    input clk,
    input rst_n,

    input rx_rdy,
    input [7:0] rx_data,
    output reg rx_rdy_clr,

    input tx_busy,
    output reg [7:0] tx_data,
    output reg tx_wr_en,

    input [31:0] reg_rdata,
    output reg reg_wr_en,
    output reg reg_rd_en,
    output reg [7:0] reg_addr,
    output reg [31:0] reg_wdata,
    output reg kick_en
);

    localparam CMD_WRITE = 8'h01;
    localparam CMD_READ  = 8'h02;
    localparam CMD_KICK  = 8'h03;
    localparam CMD_GETSTATUS = 8'h04;

    localparam [7:0] CTRL = 8'h00;
    localparam [7:0] TWD_MS = 8'h04;
    localparam [7:0] TRST_MS = 8'h08;
    localparam [7:0] ARM_DELAY_US = 8'h0C;
    localparam [7:0] STATUS = 8'h10;

    reg [2:0] rx_state;
    localparam RX_IDLE = 3'd0;
    localparam RX_CMD = 3'd1;
    localparam RX_ADDR = 3'd2;
    localparam RX_LEN = 3'd3;
    localparam RX_DATA = 3'd4;
    localparam RX_CHK = 3'd5;

    reg [3:0] tx_state;
    reg [3:0] tx_next_state;
    localparam TX_IDLE = 4'd0;
    localparam TX_EXEC = 4'd1;
    localparam TX_HDR = 4'd2;
    localparam TX_CMD = 4'd3;
    localparam TX_ADDR = 4'd4;
    localparam TX_LEN = 4'd5;
    localparam TX_DATA3 = 4'd6;         // mỗi byte chứa 8-bit, tổng 32-bit
    localparam TX_DATA2 = 4'd7;
    localparam TX_DATA1 = 4'd8;
    localparam TX_DATA0 = 4'd9;
    localparam TX_CHK = 4'd10;
    localparam TX_WAIT = 4'd11;

    reg [7:0] cmd_reg, addr_reg, len_reg, calc_chk, data_cnt, tx_chk_calc;
    reg [31:0] data_buf, tx_resp_data;

    reg rx_ack_flag;
    reg frame_rdy;

    // 1. receiver
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= RX_IDLE;
            rx_rdy_clr <= 0;
            rx_ack_flag <= 0;
            calc_chk <= 0;
            data_cnt <= 0;
            cmd_reg <= 0;
            addr_reg <= 0;
            len_reg <= 0;
            data_buf <= 0;
            frame_rdy <= 0;
        end 
        else begin
            frame_rdy <= 0;     
            if (rx_rdy && !rx_ack_flag) begin
                rx_rdy_clr <= 1'b1;
                rx_ack_flag <= 1'b1;
                case (rx_state) 
                    RX_IDLE: begin
                        if (rx_data == 8'h55) begin
                            rx_state <= RX_CMD;
                            calc_chk <= 8'h00; 
                        end
                    end

                    RX_CMD: begin
                        cmd_reg <= rx_data;
                        calc_chk <= calc_chk ^ rx_data;
                        rx_state <= RX_ADDR;
                    end

                    RX_ADDR: begin
                        addr_reg <= rx_data;
                        calc_chk <= calc_chk ^ rx_data;
                        rx_state <= RX_LEN;
                    end

                    RX_LEN: begin
                        len_reg <= rx_data;
                        calc_chk <= calc_chk ^ rx_data;
                        data_cnt <= 0;
                        data_buf <= 0;
                        if (rx_data == 0) begin
                            rx_state <= RX_CHK;
                        end 
                        else begin
                            rx_state <= RX_DATA;
                        end
                    end

                    RX_DATA: begin
                        data_buf <= (data_buf << 8) + rx_data;     // another way:data_buf <= {data_buf[23:0], rx_data}; 
                        calc_chk <= calc_chk ^ rx_data;            // Nghĩa là lấy 24 LSB của data_buf, 
                        data_cnt <= data_cnt + 1;                  // dịch trái 8 bit và thêm rx_data vào 8 bit LSB
                        if (data_cnt == len_reg - 1) begin
                            rx_state <= RX_CHK;
                        end
                    end

                    RX_CHK: begin
                        if (calc_chk == rx_data) begin
                            frame_rdy <= 1'b1;
                        end
                        rx_state <= RX_IDLE;
                    end
                endcase
            end
            else if (!rx_rdy) begin
                rx_rdy_clr <= 1'b0;    
                rx_ack_flag <= 1'b0;
            end
            else begin
                rx_rdy_clr <= 1'b1; //
            end
        end
    end

    // 2. execution and transmitter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= TX_IDLE;
            tx_wr_en <= 0;
            reg_wr_en <= 0;
            reg_rd_en <= 0;
            kick_en <= 0;
            reg_addr <= 0;
            reg_wdata <= 0;
            tx_resp_data <= 0;
            tx_chk_calc <= 0;
        end
        else begin
            tx_wr_en <= 0;
            reg_wr_en <= 0;
            reg_rd_en <= 0;
            kick_en <= 0;
            case (tx_state)
                TX_IDLE: begin
                    if (frame_rdy) begin
                        reg_addr <= addr_reg;
                        reg_wdata <= data_buf;
                        case (cmd_reg)
                            CMD_WRITE: begin
                                reg_wr_en <= 1'b1;
                            end
                            CMD_READ: begin
                                reg_rd_en <= 1'b1;
                            end
                            CMD_KICK: begin
                                kick_en <= 1'b1;
                            end
                            CMD_GETSTATUS: begin
                                reg_addr <= 8'h10;     // STATUS register address
                                reg_rd_en <= 1'b1;
                            end
                        endcase
                        tx_state <= TX_EXEC;
                    end
                end

                TX_EXEC: begin
                    tx_resp_data <= reg_rdata;
                    tx_chk_calc <= 8'd0;
                    tx_state <= TX_HDR;
                end

                TX_HDR: begin
                    if (!tx_busy) begin
                        tx_data <= 8'h55;   
                        tx_wr_en <= 1'b1;
                        tx_state <= TX_WAIT;
                        tx_next_state <= TX_CMD;
                    end
                end

                TX_CMD: begin
                    if (!tx_busy) begin
                        tx_data <= cmd_reg | 8'h80;   // set MSB to indicate response;
                        tx_wr_en <= 1'b1;
                        tx_chk_calc <= tx_chk_calc ^ (cmd_reg | 8'h80);
                        tx_state <= TX_WAIT;
                        tx_next_state <= TX_ADDR;
                    end
                end

                TX_ADDR: begin
                    if (!tx_busy) begin
                        tx_data <= addr_reg;
                        tx_wr_en <= 1'b1;
                        tx_chk_calc <= tx_chk_calc ^ addr_reg;
                        tx_state <= TX_WAIT;
                        tx_next_state <= TX_LEN;
                    end
                end

                TX_LEN: begin
                    if (!tx_busy) begin
                        tx_data <= 8'h04;   
                        tx_wr_en <= 1'b1;
                        tx_chk_calc <= tx_chk_calc ^ 8'h04;
                        tx_state <= TX_WAIT;
                        tx_next_state <= TX_DATA3;
                    end
                end

                TX_DATA3: begin
                    if (!tx_busy) begin
                        tx_data <= tx_resp_data[31:24];
                        tx_wr_en <= 1'b1;
                        tx_chk_calc <= tx_chk_calc ^ tx_resp_data[31:24];  
                        tx_state <= TX_WAIT;
                        tx_next_state <= TX_DATA2;
                    end
                end

                TX_DATA2: begin
                    if (!tx_busy) begin
                        tx_data <= tx_resp_data[23:16];
                        tx_wr_en <= 1'b1;
                        tx_chk_calc <= tx_chk_calc ^ tx_resp_data[23:16];  
                        tx_state <= TX_WAIT;
                        tx_next_state <= TX_DATA1;
                    end
                end

                TX_DATA1: begin
                    if (!tx_busy) begin
                        tx_data <= tx_resp_data[15:8];
                        tx_wr_en <= 1'b1;
                        tx_chk_calc <= tx_chk_calc ^ tx_resp_data[15:8];  
                        tx_state <= TX_WAIT;
                        tx_next_state <= TX_DATA0;
                    end
                end

                TX_DATA0: begin
                    if (!tx_busy) begin
                        tx_data <= tx_resp_data[7:0];
                        tx_wr_en <= 1'b1;
                        tx_chk_calc <= tx_chk_calc ^ tx_resp_data[7:0];  
                        tx_state <= TX_WAIT;
                        tx_next_state <= TX_CHK;
                    end
                end

                TX_CHK: begin
                    if (!tx_busy) begin
                        tx_data <= tx_chk_calc;
                        tx_wr_en <= 1'b1;
                        tx_state <= TX_WAIT;
                        tx_next_state <= TX_IDLE;
                    end
                end

                TX_WAIT: begin
                    if (!tx_busy) begin
                        tx_state <= tx_next_state;
                    end
                end
            endcase
        end
    end
endmodule