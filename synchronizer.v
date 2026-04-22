module synchronizer_debounce_fallingedge (
    input clk,
    input rst_n,
    input B_s1,
    input B_s2,
    output wdi_button,
    output reg en_button
);
    reg wdi_ff1;
    reg wdi_ff2;
    reg wdi_deb;
    reg wdi_ff3;
    reg en_ff1;
    reg en_ff2;
    reg en_deb;
    reg en_ff3;
    reg [31:0] cnt_deb_wdi;
    reg [31:0] cnt_deb_en;

    parameter DEBOUNCE_MS = 20;
    parameter CLK_FREQ_HZ = 27_000_000;
    localparam COUNTER_MAX = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS; 

    // Synchonize
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wdi_ff1 <= 1'b1;
            wdi_ff2 <= 1'b1;
        end 
        else begin
            wdi_ff1 <= B_s1;
            wdi_ff2 <= wdi_ff1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en_ff1 <= 1'b0;
            en_ff2 <= 1'b0;
        end 
         else begin
            en_ff1 <= B_s2;
            en_ff2 <= en_ff1;
        end
    end


    // Debounce
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_deb_wdi <= 1'b0;
            wdi_deb <= 1'b1;
        end
        else begin
            if (wdi_deb != wdi_ff2) begin
                cnt_deb_wdi <= cnt_deb_wdi + 1;
                if (cnt_deb_wdi >= COUNTER_MAX) begin
                    wdi_deb <= wdi_ff2;
                    cnt_deb_wdi <= 1'b0;
                end
            end
            else begin
                cnt_deb_wdi <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_deb_en <= 1'b0;
            en_deb <= 1'b0;
        end
        else begin
            if (en_deb != en_ff2) begin
                cnt_deb_en <= cnt_deb_en + 1;
                if (cnt_deb_en >= COUNTER_MAX) begin
                    en_deb <= en_ff2;
                    cnt_deb_en <= 1'b0;
                end
            end
            else begin
                cnt_deb_en <= 1'b0;
            end
        end
    end

    // Falling edge
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wdi_ff3 <= 1'b1;
        end
        else begin
            wdi_ff3 <= wdi_deb;
        end
    end
    // deb = present / ff = prev
    assign wdi_button = !(!wdi_deb & wdi_ff3);

     always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en_ff3 <= 1'b0;
        end
        else begin
            en_ff3 <= en_deb;

        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en_button <= 1'b0;
        end
        else begin
            if (!en_deb & en_ff3) begin
                en_button <= !en_button;
            end
            else begin
                en_button <= en_button;
            end
        end
    end

endmodule