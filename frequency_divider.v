module frequency_divider (
    input clk,
    input rst_n,
    output clk_en_o
);

    parameter CLK_FREQ_HZ = 27_000_000;
    parameter CLK_FREQ_DESTINATION_HZ = 1;
    parameter CLK_RATIO = CLK_FREQ_HZ / CLK_FREQ_DESTINATION_HZ;
    parameter COUNTER_MAX = CLK_RATIO - 1;
    parameter COUNTER_WIDTH = $clog2(COUNTER_MAX + 1);

    reg [COUNTER_WIDTH-1:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= {COUNTER_WIDTH{1'b0}};
        end
        else begin 
            if (cnt >= COUNTER_MAX) begin
                cnt <= {COUNTER_WIDTH{1'b0}};
            end
            else begin
                cnt <= cnt + 1'b1;
            end
        end
    end

    assign clk_en_o = (cnt == COUNTER_MAX);

endmodule
