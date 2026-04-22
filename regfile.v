module regfile (
    input clk,
    input rst_n,

    input reg_wr_en,
    input reg_rd_en,
    input [7:0] reg_addr,
    input [31:0] reg_wdata,
    input kick_en,
    output reg [31:0] reg_rdata,

    output kick_sw,
    output en_sw,
    output wdi_src,
    output [31:0] tWD_ms,
    output [31:0] tRST_ms,
    output [15:0] arm_delay_us,

    input core_last_kick_src,
    input core_wdo,
    input core_enout,
    input core_FaultActive,
    input core_en_effective
);

    reg [31:0] ctrl_reg;
    reg [31:0] tWD_reg;
    reg [31:0] tRST_reg;
    reg [15:0] arm_delay_reg;
    wire [31:0] status;

    assign kick_sw = kick_en;
    assign en_sw = ctrl_reg[0];
    assign wdi_src = ctrl_reg[1];
    assign tWD_ms = tWD_reg;
    assign tRST_ms = tRST_reg;
    assign arm_delay_us = arm_delay_reg;
    assign status = {27'd0, core_last_kick_src, core_wdo, core_enout, core_FaultActive, core_en_effective};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_reg <= 32'd00;     // bit 1: wdi_src (0 = button, 1 = software), bit 0: en_sw (0 = dis, 1 = en)
            tWD_reg <= 32'd1600;
            tRST_reg <= 32'd200;
            arm_delay_reg <= 16'd150;
        end
        else begin
            if (reg_wr_en) begin
                case (reg_addr) 
                    8'h00: begin
                        ctrl_reg[1:0] <= reg_wdata[1:0];
                    end
                    8'h04: begin
                        tWD_reg <= reg_wdata;
                    end
                    8'h08: begin
                        tRST_reg <= reg_wdata;
                    end
                    8'h0C: begin
                        arm_delay_reg <= reg_wdata[15:0];
                    end
                endcase
            end
        end
    end

    always @(*) begin
        case (reg_addr) 
            8'h00: reg_rdata = ctrl_reg;
            8'h04: reg_rdata = tWD_reg;
            8'h08: reg_rdata = tRST_reg;
            8'h0C: reg_rdata = {16'd0, arm_delay_reg};
            8'h10: reg_rdata = status;
            default: reg_rdata = 32'h0;
        endcase
    end 

endmodule