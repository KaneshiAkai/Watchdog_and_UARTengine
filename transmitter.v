module transmitter (
    input  wire clk,
    input  wire rst_n,
    input  wire wr_en,
    input  wire clk_en,
    input  wire [7:0] data_in,
    
    output reg  tx,
    output wire tx_busy
);

    reg [2:0] index; // Chỉ cần 3 bit (0 đến 7) là đủ để đếm 8 phần tử
    reg [7:0] data;
    reg [1:0] state; // Tối ưu hóa memory: Chỉ có 4 trạng thái nên dùng 2 bit

    localparam [1:0] S_IDLE  = 2'd0;
    localparam [1:0] S_START = 2'd1;
    localparam [1:0] S_DATA  = 2'd2;
    localparam [1:0] S_STOP  = 2'd3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            index <= 3'd0;
            tx    <= 1'b1;
            state <= S_IDLE;
            data  <= 8'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx <= 1'b1;
                    if (wr_en) begin
                        data  <= data_in; // Chốt dữ liệu
                        state <= S_START;
                    end
                end

                S_START: begin
                    if (clk_en) begin
                        tx    <= 1'b0;    // Bắt đầu START bit ngay tại nhịp clk_en này
                        state <= S_DATA;
                        index <= 3'd0;
                    end
                end

                S_DATA: begin
                    if (clk_en) begin
                        tx <= data[index]; // Bắt đầu truyền data[index]
                        
                        if (index == 3'd7) begin
                            state <= S_STOP; // Nếu là bit cuối, nhịp clk_en tiếp theo sẽ sang S_STOP
                        end else begin
                            index <= index + 1'b1;
                        end
                    end
                end

                S_STOP: begin
                    if (clk_en) begin
                        tx    <= 1'b1;    // Bắt đầu STOP bit
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign tx_busy = (state != S_IDLE);

endmodule