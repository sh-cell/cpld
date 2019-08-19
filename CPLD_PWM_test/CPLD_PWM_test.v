module CPLD_PWM_test(
							clk,
							rst_n,
							LED1,
							LED2,
							LED3,
							Driver,
							pout1,
							pout2,
							pout3,
							Enable,
							//spi
							spi_cs,
							spi_sck,
							spi_si,     //miso 没用到所以没有定义
							//uart_receive
							uart_rxd,     //
							//uart_trans
							uart_txd,     //
							);
							
input clk;
input rst_n;
output LED1;
output LED2;
output LED3;
output Driver;
output pout1;
output pout2;
output pout3;
output Enable;
//spi
input spi_cs;
input spi_sck;
input spi_si;
//uart rxd
input uart_rxd;
//uart txd
output uart_txd;

reg LED1;
reg LED2;
reg LED3;
reg Driver;
reg pout1;//用来将接收到的数据可视化
reg pout2;
reg pout3;
reg Enable = 1'b0;

reg [15:0] cnt = 16'd0;
reg [15:0] cnt_real = 16'd0;
reg [15:0] pwm = 16'd5000;
reg [31:0] clck = 32'd0;

//spi
reg spi_cs_0;
reg spi_cs_1;
reg spi_sck_0;
reg spi_sck_1;
reg spi_si_0;

wire cs;//用于存片选信号
wire spi_cs_pos;//用于捕捉cs信号的上升沿
wire spi_sck_pos;//用于捕捉sck信号的上升沿
wire spi_data;//用于存输入口的数据，可能这种方式正确度更好？

reg [3:0] rxd_cnt;
reg [15:0] rxd_data_temp;//暂存接收到的数据
reg [15:0] rxd_data;//最终一次发送所接收到的数据
reg spi_delay;
//spi*

//uart rxd
localparam baud_cnt_end = 8'd172;//波特率计数器上限，115200bps  8680ns  8680/50=173
localparam baud_cnt_m = 8'd86;//波特率计数器中点，在此点数据比较稳定，方便存入数据

reg [7:0] uart_rxd_data_temp;//暂存收到的数据
reg [7:0] uart_rxd_data;//最终存入的数据
reg uart_fina_temp;//存入结束位，用来判定是否传输有问题
reg uart_fina;//存入结束位，用来判定是否传输有问题
reg uart_rxd_0;
reg uart_rxd_1;//捕捉起始位下降沿
reg uart_rxd_flag;//表示接收到了起始位，初始为0，开始接收数据为1，接收完后清0
reg [7:0] rxd_baud_cnt;//波特率计数器，每计数完一次清零，表示接收了一位，在技术中点处写入数据到temp
reg rxd_bit_flag;//波特率计数器计到中点时从0置1，表示可以将引脚数据写入temp了
reg [3:0] rxd_bit_cnt;//表示数据传输到哪一位了，0表示起始位，1到8为数据位，9为结束位

wire uart_neg;//捕捉起始位
//uart rxd*

//uart txd
reg uart_txd;
reg [7:0] uart_txd_data;//需要发送的数据
reg [7:0] uart_txd_test;//用于存储写到uart_txd中的数据，看是否正确 点灯用 ////////
reg uart_txd_en;//发送使能，用于程序计算完或通过spi通信接收完数据后，产生的发送使能
reg uart_txd_flag;//发送标志位，表示进入数据发送阶段
reg [7:0] txd_baud_cnt;//
reg [3:0] txd_bit_cnt;//表示数据传输到哪一位了，0表示起始位，1到8为数据位，9为结束位
//uart txd*

//spi program
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		spi_cs_0 <= 1'b1;
		spi_cs_1 <= 1'b1;
		spi_sck_0 <= 1'b0;
		spi_sck_1 <= 1'b0;
		spi_si_0 <= 1'b0;
		spi_delay <= 1'b0;
	end
	else begin
		spi_cs_0 <= spi_cs;
		spi_cs_1 <= spi_cs_0;
		spi_si_0 <= spi_si;//这里赋值两次会导致上升沿超前于数据
		spi_sck_0 <= spi_sck;
		spi_sck_1 <= spi_sck_0;
	end
end
assign spi_data = spi_si_0;//存入
assign cs = spi_cs_1;//存入
assign spi_cs_pos = spi_cs_0 & (~spi_cs_1);//捕捉上升沿
assign spi_sck_pos = spi_sck_0 & (~spi_sck_1);//捕捉上升沿

always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		rxd_cnt <= 4'd0;
		rxd_data_temp <= 16'd0;
	end
	else if(!cs) begin
		if(spi_sck_pos) begin		
			rxd_data_temp[4'd15-rxd_cnt] <= spi_data;
			rxd_cnt <= rxd_cnt+4'd1;
		end
		else begin
			rxd_data_temp <= rxd_data_temp;
			rxd_cnt <= rxd_cnt;
		end
	end
	else begin
		rxd_data_temp <= rxd_data_temp;
		rxd_cnt <= 4'd0;
	end
end

always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		rxd_data <= 16'd0;
	end
	else if(spi_cs_pos) begin
		rxd_data <= rxd_data_temp;
	end
	else begin
		rxd_data <= rxd_data;
	end
end
//spi end

//uart rxd
//捕捉下降沿，即开开始信号
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		uart_rxd_0 <= 1'b0;
		uart_rxd_1 <= 1'b0;
	end
	else begin
		uart_rxd_0 <= uart_rxd;
		uart_rxd_1 <=uart_rxd_0;
	end
end
assign uart_neg = uart_rxd_1 & (~uart_rxd_0);//捕捉下降沿

//生成接收标志位，作为数据接收的判断
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		uart_rxd_flag <= 1'b0;
	end
	else begin
		if((uart_neg) && (!uart_rxd_flag)) begin
			uart_rxd_flag <= 1'b1;
		end
		else if((rxd_bit_cnt == 4'd9) && (rxd_baud_cnt == baud_cnt_end)) begin  //第九位用来存结束标志位，来验证是否有问题
			uart_rxd_flag <= 1'b0;
		end
	end
end

//在接收数据的时候，波特率计数器开始计数
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		rxd_baud_cnt <=8'b0;
	end
	else if(rxd_baud_cnt == baud_cnt_end) begin
		rxd_baud_cnt <= 8'b0;
	end
	else if(uart_rxd_flag) begin
		rxd_baud_cnt <= rxd_baud_cnt + 1'b1;
	end
	else begin
		rxd_baud_cnt <= 8'b0;
	end
end

//定义位接收标志位，当波特率计数器计到中点时候，此时允许将引脚上的数据写入temp
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		rxd_bit_flag <= 1'b0;
	end
	else if(rxd_baud_cnt == baud_cnt_m) begin
		rxd_bit_flag <= 1'b1;
	end
	else begin
		rxd_bit_flag <= 1'b0;
	end
end

//每次波特率计数器到达上限的时候，bit位数加一，表示进入下一位，直到接收标志位清零而清零
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		rxd_bit_cnt <= 4'd0;
	end
	else if((rxd_baud_cnt == baud_cnt_end) && (uart_rxd_flag)) begin
		rxd_bit_cnt <= rxd_bit_cnt + 4'd1;
	end
	else if(uart_rxd_flag == 1'b0) begin
		rxd_bit_cnt <= 4'd0;
	end
end

//写入数据
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		uart_rxd_data_temp <= 8'd0;
	end
	else if(uart_rxd_flag) begin
		if(rxd_bit_flag) begin
			case(rxd_bit_cnt)
				4'd1: begin
					uart_rxd_data_temp[0] <= uart_rxd_0;
				end
				4'd2: begin
					uart_rxd_data_temp[1] <= uart_rxd_0;
				end
				4'd3: begin
					uart_rxd_data_temp[2] <= uart_rxd_0;
				end
				4'd4: begin
					uart_rxd_data_temp[3] <= uart_rxd_0;
				end
				4'd5: begin
					uart_rxd_data_temp[4] <= uart_rxd_0;
				end
				4'd6: begin
					uart_rxd_data_temp[5] <= uart_rxd_0;
				end
				4'd7: begin
					uart_rxd_data_temp[6] <= uart_rxd_0;
				end
				4'd8: begin
					uart_rxd_data_temp[7] <= uart_rxd_0;
				end
				4'd9: begin
					uart_fina_temp <= uart_rxd_0;
				end
				default: begin
					uart_rxd_data_temp <= uart_rxd_data_temp;
					uart_fina_temp <= uart_fina;
				end
			endcase
		end
		else begin
			uart_rxd_data_temp <= uart_rxd_data_temp;
			uart_fina_temp <= uart_fina;
		end
	end
	else begin
		uart_rxd_data_temp <= uart_rxd_data_temp;
		uart_fina_temp <= uart_fina_temp;
	end
end

//最终转存
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		uart_rxd_data <= 8'd0;
		uart_fina <= 1'b0;
	end
	else if((rxd_bit_cnt == 4'd8) && (rxd_baud_cnt == baud_cnt_end - 8'd1)) begin
		uart_rxd_data <= uart_rxd_data_temp;
	end
	else if((rxd_bit_cnt == 4'd9) && (rxd_baud_cnt == baud_cnt_end - 8'd1)) begin
		uart_fina <= uart_fina_temp;
	end
	else begin
		uart_rxd_data <= uart_rxd_data;
		uart_fina <= uart_fina;
	end
end
//uart rxd*

//uart txd
//延迟模拟产生uart_txd_en以及给uart_txd_data赋值  1000us
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		uart_txd_en <= 1'b0;
		uart_txd_data <= 8'd0;
	end
	else if(cnt == 0) begin
		uart_txd_en <= 1'b1;
		uart_txd_data <= 8'b00110110;
	end
	else begin
		uart_txd_en <= 1'b0;
		uart_txd_data <= 8'b00110110;
	end
end

//传输flag
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		uart_txd_flag <= 1'b0;
	end
	else if((uart_txd_en) && (!uart_txd_flag)) begin  //这里搞两个判断是为了保证在flag被置1的时候不会再进这里了
		uart_txd_flag <= 1'b1;
	end
	else if((txd_bit_cnt == 4'd9) && (txd_baud_cnt == baud_cnt_end)) begin  //结束位传完flag置0 
		uart_txd_flag <= 1'b0;
	end
end

//记录txd_baud_cnt
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		txd_baud_cnt <= 8'd0;
	end
	else if(txd_baud_cnt == baud_cnt_end) begin
		txd_baud_cnt <= 8'd0;
	end
	else if(uart_txd_flag) begin
		txd_baud_cnt <= txd_baud_cnt + 8'd1;
	end
	else begin
		txd_baud_cnt <= 8'd0;
	end
end


//记录txd_bit_cnt
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		txd_bit_cnt <= 4'd0;
	end
	else if(txd_baud_cnt == baud_cnt_end) begin
		txd_bit_cnt <= txd_bit_cnt + 4'd1;
	end
	else if(uart_txd_flag == 1'b0) begin
		txd_bit_cnt <= 4'd0;
	end
	else begin
		txd_bit_cnt <= txd_bit_cnt;
	end
end

//将数据写入引脚 传输出去
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		uart_txd <= 1'b1;//没有数据的时候 txd要一直发高电平  因为第一个低电平为起始位
	end
	else if(uart_txd_flag) begin
		case(txd_bit_cnt)
			4'd0: begin
				uart_txd <= 1'b0;
			end
			4'd1: begin
				uart_txd <= uart_txd_data[0];
				uart_txd_test[0] <= uart_txd;
			end
			4'd2: begin
				uart_txd <= uart_txd_data[1];
				uart_txd_test[1] <= uart_txd;
			end
			4'd3: begin
				uart_txd <= uart_txd_data[2];
				uart_txd_test[2] <= uart_txd;
			end
			4'd4: begin
				uart_txd <= uart_txd_data[3];
				uart_txd_test[3] <= uart_txd;
			end
			4'd5: begin
				uart_txd <= uart_txd_data[4];
				uart_txd_test[4] <= uart_txd;
			end
			4'd6: begin
				uart_txd <= uart_txd_data[5];
				uart_txd_test[5] <= uart_txd;
			end
			4'd7: begin
				uart_txd <= uart_txd_data[6];
				uart_txd_test[6] <= uart_txd;
			end
			4'd8: begin
				uart_txd <= uart_txd_data[7];
				uart_txd_test[7] <= uart_txd;
			end
			4'd9: begin
				uart_txd <= 1'b1;
			end
			default: begin
				uart_txd <= 1'b1;
			end
		endcase
	end
	else begin
		uart_txd <= 1'b1;
	end
end
//uart txd*

//LED test
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		LED1 = 1'b0;
	end
	else if(uart_txd_test == 8'b00110110) begin
		LED1 = 1'b1;
	end
	else begin
		LED1 = 1'b0;
	end
end

always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		LED2 = 1'b0;
	end
	else if(uart_rxd_data == 8'b00110110) begin
		LED2 = 1'b1;
	end
	else begin
		LED2 = 1'b0;
	end 
end

always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
		LED3 = 1'b0;
	end
	else begin
		LED3 = 1'b1;
	end	
end

//LED test end

//PWM
always @(posedge clk) begin
	if(cnt>16'd19999) begin
		cnt=16'd0;
		cnt_real=16'd0;
	end
	else if(cnt<10000) begin
		cnt=cnt+16'd1;
		cnt_real=cnt_real+16'd1;
	end
	else begin
		cnt=cnt+16'd1;
		cnt_real=cnt_real-16'd1;
	end
end

always @(posedge clk) begin
	if(pwm>=cnt_real) begin
		Driver=1'b1;
		pout1 = 1'b1;
		pout2 = 1'b1;
		pout3 = 1'b1;
	end
	else begin
		Driver=1'b0;
		pout1 = 1'b0;
		pout2 = 1'b0;
		pout3 = 1'b0;
	end
end
//PWM end

endmodule
