module wd_top_module (
    input clk,
    input B_s1,
    input B_s2,
    input uart_rx,
    // input wdi_src_mode,  // 0 = button, 1 = software

    output uart_tx,
    output wdo,
    output en_o
);
    wire rst_n;
    wire tick_us;
    wire tick_ms;
    wire wdi_button;
    wire en_button;

    wire baud_rx_en;
    wire baud_tx_en;

    wire rx_rdy;
    wire [7:0] rx_data;
    wire rx_rdy_clr;

    wire tx_busy;
    wire [7:0] tx_data;
    wire tx_wr_en;

    wire reg_wr_en;
    wire reg_rd_en;
    wire [7:0] reg_addr;
    wire [31:0] reg_wdata;
    wire [31:0] reg_rdata;
    wire kick_en;

    wire kick_sw;
    wire en_sw;
    wire wdi_src;

    wire core_fault_active;
    wire core_last_kick_src;
    wire core_en_effective;

    wire wdi_sw;
    wire [31:0] tWD_ms;
    wire [31:0] tRST_ms;
    wire [15:0] arm_delay_us;

    assign wdi_sw = ~kick_sw;


    frequency_divider #(.CLK_FREQ_DESTINATION_HZ(1_000_000)) microsecond (
        .clk(clk),
        .rst_n(rst_n),
        .clk_en_o(tick_us)
    );

    frequency_divider #(.CLK_FREQ_DESTINATION_HZ(1_000)) millisecond (
        .clk(clk),
        .rst_n(rst_n),
        .clk_en_o(tick_ms)
    );

    baudrate_gen baudrate_gen_inst (
        .clk(clk),
        .rx_en(baud_rx_en),
        .tx_en(baud_tx_en)
    );

    receiver receiver_inst (
        .clk(clk),
        .rst_n(rst_n),
        .rdy_clr(rx_rdy_clr),
        .clk_en(baud_rx_en),
        .rx(uart_rx),
        .rdy(rx_rdy),
        .data_out(rx_data)
    );

    transmitter transmitter_inst (
        .clk(clk),
        .wr_en(tx_wr_en),
        .clk_en(baud_tx_en),
        .rst_n(rst_n),
        .data_in(tx_data),
        .tx(uart_tx),
        .tx_busy(tx_busy)
    );

    frame_parser frame_parser_inst (
        .clk(clk),
        .rst_n(rst_n),
        .rx_rdy(rx_rdy),
        .rx_data(rx_data),
        .rx_rdy_clr(rx_rdy_clr),
        .tx_busy(tx_busy),
        .tx_data(tx_data),
        .tx_wr_en(tx_wr_en),
        .reg_rdata(reg_rdata),
        .reg_wr_en(reg_wr_en),
        .reg_rd_en(reg_rd_en),
        .reg_addr(reg_addr),
        .reg_wdata(reg_wdata),
        .kick_en(kick_en)
    );

    watchdog_core watchdog_core_inst (
        .clk(clk),
        .rst_n(rst_n),
        .wdi_sw(wdi_sw),
        .en_sw(en_sw),
        .wdi_button(wdi_button),
        .en_button(en_button),
        .wdi_src(wdi_src),
        .tick_us(tick_us),
        .tick_ms(tick_ms),
        .tWD_ms(tWD_ms),
        .tRST_ms(tRST_ms),
        .arm_delay_us(arm_delay_us),
        .wdo(wdo),
        .en_o(en_o),
        .FaultActive(core_fault_active),
        .last_kick_src(core_last_kick_src),
        .en_effective(core_en_effective)
    );

    internal_rst internal_rst_inst (
        .clk(clk),
        .rst_n(rst_n)
    );

    regfile regfile_inst (
        .clk(clk),
        .rst_n(rst_n),
        .reg_wr_en(reg_wr_en),
        .reg_rd_en(reg_rd_en),
        .reg_addr(reg_addr),
        .reg_wdata(reg_wdata),
        .kick_en(kick_en),
        .reg_rdata(reg_rdata),
        .kick_sw(kick_sw),
        .en_sw(en_sw),
        .wdi_src(wdi_src),
        .tWD_ms(tWD_ms),
        .tRST_ms(tRST_ms),
        .arm_delay_us(arm_delay_us),
        .core_last_kick_src(core_last_kick_src),
        .core_wdo(wdo),
        .core_enout(en_o),
        .core_FaultActive(core_fault_active),
        .core_en_effective(core_en_effective)
    );

    synchronizer_debounce_fallingedge synchronizer_debounce_fallingedge_inst (
        .clk(clk),
        .rst_n(rst_n),
        .B_s1(B_s1),
        .B_s2(B_s2),
        .wdi_button(wdi_button),
        .en_button(en_button)
    );

endmodule