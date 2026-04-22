module internal_rst (
    input clk,
    output rst_n
);
    reg [15:0] rst_cnt = 16'd0;

    always @(posedge clk) begin
        if (rst_cnt != 16'hFFFF) begin
            rst_cnt <= rst_cnt + 1'b1;
        end
    end

    assign rst_n = (rst_cnt == 16'hFFFF);

endmodule