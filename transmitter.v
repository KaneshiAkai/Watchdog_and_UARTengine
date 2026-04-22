module transmitter (
    input clk,
    input wr_en,
    input clk_en,
    input rst_n,
    input [7:0] data_in,
    output reg tx,
    output tx_busy
);

    reg [3:0] index;
    reg [7:0] data;
    reg [2:0] state;

    localparam [2:0] S_IDLE  = 3'd0;
    localparam [2:0] S_START = 3'd1;
    localparam [2:0] S_DATA  = 3'd2;
    localparam [2:0] S_STOP  = 3'd3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            index <= 4'd0;
            tx <= 1'b1;
        end
        else begin
            case (state)
                S_IDLE: begin
                    tx <= 1'b1;
                    if (wr_en) begin
                        data <= data_in;      // chỉ lấy data khi có tín hiệu wr_en
                        state <= S_START;
                    end
                    else begin
                        state <= S_IDLE;
                    end
                end

                S_START: begin
                    if (clk_en)begin
                        state <= S_DATA;
                        tx  <= 1'b0;        // start bit
                        index <= 4'd0;
                    end
                    else begin
                        state <= S_START;
                    end
                end

                S_DATA: begin
                    if (clk_en)begin
                        if (index == 4'd8) begin
                            index <= 4'd0;
                            state <= S_STOP;
                        end 
                        else begin
                            state <= S_DATA;
                            index <= index + 4'd1;
                            tx <= data[index];       // data bits
                        end
                    end
                end

                S_STOP: begin
                    if (clk_en)begin
                        tx <= 1'b1;        // stop bit
                        state <= S_IDLE;
                    end
                end

                default: begin
                    tx <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

    assign tx_busy = (state != S_IDLE);
endmodule