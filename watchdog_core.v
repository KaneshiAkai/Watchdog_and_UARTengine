module watchdog_core (
    input clk,
    input rst_n,

    input wdi_sw,
    input en_sw,
    input wdi_button,
    input en_button,
    input wdi_src,  // 0 = button, 1 = software

    input tick_us,
    input tick_ms,

    input [31:0] tWD_ms,
    input [31:0] tRST_ms,
    input [15:0] arm_delay_us,

    output reg wdo,
    output reg en_o,
    output reg FaultActive,
    output reg last_kick_src,  // 0 = button, 1 = software
    output reg en_effective
);

    reg [31:0] delay_cnt;
    reg [31:0] tWD_cnt;
    reg [31:0] tRST_cnt;
    reg wdi;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            delay_cnt <= 32'd0;
            tWD_cnt <= 32'd0;
            tRST_cnt <= 32'd0;
            wdo <= 1'b1;
            en_o <= 1'b0;
            FaultActive <= 1'b0;
            last_kick_src <= 1'b0;
            en_effective <= 1'b0;
            wdi <= 1'b1;
        end
        else begin
            en_o <= (wdi_src) ? en_sw : en_button;
            if (!en_o) begin
                en_effective <= en_o;
                wdo <= 1'b1;
                FaultActive <= 1'b0;
            end 

            if (delay_cnt <= arm_delay_us) begin    // arm_delay
                if (tick_us) begin
                    delay_cnt <= delay_cnt + 1;
                    tRST_cnt <= 1'b0; 
                    tWD_cnt <= 1'b0;
                    wdo <= 1'b1;
                end
            end
            else begin
                en_effective <= en_o;
                wdi <= (wdi_src) ? wdi_sw : wdi_button;
                if (tick_ms) begin
                    tWD_cnt <= tWD_cnt + 1;
                end

                if (tRST_cnt >= tRST_ms) begin  // after Fault -> arm_delay
                    wdo <= 1'b0;
                    delay_cnt <= 1'b0;
                end
                
                if (tWD_cnt >= tWD_ms) begin    // Fault condition
                    if (tick_ms) begin
                        wdo <= 1'b0;
                        tRST_cnt <= tRST_cnt + 1;
                        FaultActive <= 1'b1;
                    end
                end
                else if (!wdi) begin                 // Kick condition
                    tWD_cnt <= 1'b0;
                    if (wdi_src) begin
                        last_kick_src <= 1'b1;
                    end
                    else begin
                        last_kick_src <= 1'b0;
                    end
                end
            end
        end
    end

endmodule