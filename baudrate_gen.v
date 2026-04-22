module baudrate_gen (
    input clk,
    output rx_en,
    output tx_en
);

    parameter CLK_FREQ_HZ = 27_000_000;
    parameter BAUD_RATE = 115200;
    parameter CYCLES_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    reg [3:0] cnt_rx = 4'd0;
    reg [7:0] cnt_tx = 8'd0;

    always @(posedge clk) begin
        if (cnt_rx >= (CYCLES_PER_BIT / 16)) begin
            cnt_rx <= 4'd0;
        end
        else begin
            cnt_rx <= cnt_rx + 4'd1;
        end
    end
    assign rx_en = (cnt_rx == 4'd0);

    always @(posedge clk) begin
        if (cnt_tx >= CYCLES_PER_BIT) begin
            cnt_tx <= 8'd0;
        end
        else begin
            cnt_tx <= cnt_tx + 8'd1;
        end
    end
    assign tx_en = (cnt_tx == 8'd0);

endmodule