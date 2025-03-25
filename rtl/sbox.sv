
/*
* This sbox is random-generated. There's no guarantee on its safety from
* lineral crypto analysis attack
*/
module sbox_case(
    input   logic [7:0] data_i,
    output  logic [7:0] data_o
    );

    always_comb begin
        case (data_i)
            8'd0  : data_o=8'd99 ; 8'd1  : data_o=8'd124; 8'd2  : data_o=8'd119; 8'd3  : data_o=8'd123; 8'd4  : data_o=8'd242; 8'd5  : data_o=8'd107; 8'd6  : data_o=8'd111; 8'd7  : data_o=8'd197;
            8'd8  : data_o=8'd48 ; 8'd9  : data_o=8'd1  ; 8'd10 : data_o=8'd103; 8'd11 : data_o=8'd43 ; 8'd12 : data_o=8'd254; 8'd13 : data_o=8'd215; 8'd14 : data_o=8'd171; 8'd15 : data_o=8'd118;
            8'd16 : data_o=8'd202; 8'd17 : data_o=8'd130; 8'd18 : data_o=8'd201; 8'd19 : data_o=8'd125; 8'd20 : data_o=8'd250; 8'd21 : data_o=8'd89 ; 8'd22 : data_o=8'd71 ; 8'd23 : data_o=8'd240;
            8'd24 : data_o=8'd173; 8'd25 : data_o=8'd212; 8'd26 : data_o=8'd162; 8'd27 : data_o=8'd175; 8'd28 : data_o=8'd156; 8'd29 : data_o=8'd164; 8'd30 : data_o=8'd114; 8'd31 : data_o=8'd192;
            8'd32 : data_o=8'd183; 8'd33 : data_o=8'd253; 8'd34 : data_o=8'd147; 8'd35 : data_o=8'd38 ; 8'd36 : data_o=8'd54 ; 8'd37 : data_o=8'd63 ; 8'd38 : data_o=8'd247; 8'd39 : data_o=8'd204;
            8'd40 : data_o=8'd52 ; 8'd41 : data_o=8'd165; 8'd42 : data_o=8'd229; 8'd43 : data_o=8'd241; 8'd44 : data_o=8'd113; 8'd45 : data_o=8'd216; 8'd46 : data_o=8'd49 ; 8'd47 : data_o=8'd21 ;
            8'd48 : data_o=8'd4  ; 8'd49 : data_o=8'd199; 8'd50 : data_o=8'd35 ; 8'd51 : data_o=8'd195; 8'd52 : data_o=8'd24 ; 8'd53 : data_o=8'd150; 8'd54 : data_o=8'd5  ; 8'd55 : data_o=8'd154;
            8'd56 : data_o=8'd7  ; 8'd57 : data_o=8'd18 ; 8'd58 : data_o=8'd128; 8'd59 : data_o=8'd226; 8'd60 : data_o=8'd235; 8'd61 : data_o=8'd39 ; 8'd62 : data_o=8'd178; 8'd63 : data_o=8'd117;
            8'd64 : data_o=8'd9  ; 8'd65 : data_o=8'd131; 8'd66 : data_o=8'd44 ; 8'd67 : data_o=8'd26 ; 8'd68 : data_o=8'd27 ; 8'd69 : data_o=8'd110; 8'd70 : data_o=8'd90 ; 8'd71 : data_o=8'd160;
            8'd72 : data_o=8'd82 ; 8'd73 : data_o=8'd59 ; 8'd74 : data_o=8'd214; 8'd75 : data_o=8'd179; 8'd76 : data_o=8'd41 ; 8'd77 : data_o=8'd227; 8'd78 : data_o=8'd47 ; 8'd79 : data_o=8'd132;
            8'd80 : data_o=8'd83 ; 8'd81 : data_o=8'd209; 8'd82 : data_o=8'd0  ; 8'd83 : data_o=8'd237; 8'd84 : data_o=8'd32 ; 8'd85 : data_o=8'd252; 8'd86 : data_o=8'd177; 8'd87 : data_o=8'd91 ;
            8'd88 : data_o=8'd106; 8'd89 : data_o=8'd203; 8'd90 : data_o=8'd190; 8'd91 : data_o=8'd57 ; 8'd92 : data_o=8'd74 ; 8'd93 : data_o=8'd76 ; 8'd94 : data_o=8'd88 ; 8'd95 : data_o=8'd207;
            8'd96 : data_o=8'd208; 8'd97 : data_o=8'd239; 8'd98 : data_o=8'd170; 8'd99 : data_o=8'd251; 8'd100: data_o=8'd67 ; 8'd101: data_o=8'd77 ; 8'd102: data_o=8'd51 ; 8'd103: data_o=8'd133;
            8'd104: data_o=8'd69 ; 8'd105: data_o=8'd249; 8'd106: data_o=8'd2  ; 8'd107: data_o=8'd127; 8'd108: data_o=8'd80 ; 8'd109: data_o=8'd60 ; 8'd110: data_o=8'd159; 8'd111: data_o=8'd168;
            8'd112: data_o=8'd81 ; 8'd113: data_o=8'd163; 8'd114: data_o=8'd64 ; 8'd115: data_o=8'd143; 8'd116: data_o=8'd146; 8'd117: data_o=8'd157; 8'd118: data_o=8'd56 ; 8'd119: data_o=8'd245;
            8'd120: data_o=8'd188; 8'd121: data_o=8'd182; 8'd122: data_o=8'd218; 8'd123: data_o=8'd33 ; 8'd124: data_o=8'd16 ; 8'd125: data_o=8'd255; 8'd126: data_o=8'd243; 8'd127: data_o=8'd210;
            8'd128: data_o=8'd205; 8'd129: data_o=8'd12 ; 8'd130: data_o=8'd19 ; 8'd131: data_o=8'd236; 8'd132: data_o=8'd95 ; 8'd133: data_o=8'd151; 8'd134: data_o=8'd68 ; 8'd135: data_o=8'd23 ;
            8'd136: data_o=8'd196; 8'd137: data_o=8'd167; 8'd138: data_o=8'd126; 8'd139: data_o=8'd61 ; 8'd140: data_o=8'd100; 8'd141: data_o=8'd93 ; 8'd142: data_o=8'd25 ; 8'd143: data_o=8'd115;
            8'd144: data_o=8'd96 ; 8'd145: data_o=8'd129; 8'd146: data_o=8'd79 ; 8'd147: data_o=8'd220; 8'd148: data_o=8'd34 ; 8'd149: data_o=8'd42 ; 8'd150: data_o=8'd144; 8'd151: data_o=8'd136;
            8'd152: data_o=8'd70 ; 8'd153: data_o=8'd238; 8'd154: data_o=8'd184; 8'd155: data_o=8'd20 ; 8'd156: data_o=8'd222; 8'd157: data_o=8'd94 ; 8'd158: data_o=8'd11 ; 8'd159: data_o=8'd219;
            8'd160: data_o=8'd224; 8'd161: data_o=8'd50 ; 8'd162: data_o=8'd58 ; 8'd163: data_o=8'd10 ; 8'd164: data_o=8'd73 ; 8'd165: data_o=8'd6  ; 8'd166: data_o=8'd36 ; 8'd167: data_o=8'd92 ;
            8'd168: data_o=8'd194; 8'd169: data_o=8'd211; 8'd170: data_o=8'd172; 8'd171: data_o=8'd98 ; 8'd172: data_o=8'd145; 8'd173: data_o=8'd149; 8'd174: data_o=8'd228; 8'd175: data_o=8'd121;
            8'd176: data_o=8'd231; 8'd177: data_o=8'd200; 8'd178: data_o=8'd55 ; 8'd179: data_o=8'd109; 8'd180: data_o=8'd141; 8'd181: data_o=8'd213; 8'd182: data_o=8'd78 ; 8'd183: data_o=8'd169;
            8'd184: data_o=8'd108; 8'd185: data_o=8'd86 ; 8'd186: data_o=8'd244; 8'd187: data_o=8'd234; 8'd188: data_o=8'd101; 8'd189: data_o=8'd122; 8'd190: data_o=8'd174; 8'd191: data_o=8'd8  ;
            8'd192: data_o=8'd186; 8'd193: data_o=8'd120; 8'd194: data_o=8'd37 ; 8'd195: data_o=8'd46 ; 8'd196: data_o=8'd28 ; 8'd197: data_o=8'd166; 8'd198: data_o=8'd180; 8'd199: data_o=8'd198;
            8'd200: data_o=8'd232; 8'd201: data_o=8'd221; 8'd202: data_o=8'd116; 8'd203: data_o=8'd31 ; 8'd204: data_o=8'd75 ; 8'd205: data_o=8'd189; 8'd206: data_o=8'd139; 8'd207: data_o=8'd138;
            8'd208: data_o=8'd112; 8'd209: data_o=8'd62 ; 8'd210: data_o=8'd181; 8'd211: data_o=8'd102; 8'd212: data_o=8'd72 ; 8'd213: data_o=8'd3  ; 8'd214: data_o=8'd246; 8'd215: data_o=8'd14 ;
            8'd216: data_o=8'd97 ; 8'd217: data_o=8'd53 ; 8'd218: data_o=8'd87 ; 8'd219: data_o=8'd185; 8'd220: data_o=8'd134; 8'd221: data_o=8'd193; 8'd222: data_o=8'd29 ; 8'd223: data_o=8'd158;
            8'd224: data_o=8'd225; 8'd225: data_o=8'd248; 8'd226: data_o=8'd152; 8'd227: data_o=8'd17 ; 8'd228: data_o=8'd105; 8'd229: data_o=8'd217; 8'd230: data_o=8'd142; 8'd231: data_o=8'd148;
            8'd232: data_o=8'd155; 8'd233: data_o=8'd30 ; 8'd234: data_o=8'd135; 8'd235: data_o=8'd233; 8'd236: data_o=8'd206; 8'd237: data_o=8'd85 ; 8'd238: data_o=8'd40 ; 8'd239: data_o=8'd223;
            8'd240: data_o=8'd140; 8'd241: data_o=8'd161; 8'd242: data_o=8'd137; 8'd243: data_o=8'd13 ; 8'd244: data_o=8'd191; 8'd245: data_o=8'd230; 8'd246: data_o=8'd66 ; 8'd247: data_o=8'd104;
            8'd248: data_o=8'd65 ; 8'd249: data_o=8'd153; 8'd250: data_o=8'd45 ; 8'd251: data_o=8'd15 ; 8'd252: data_o=8'd176; 8'd253: data_o=8'd84 ; 8'd254: data_o=8'd187; 8'd255: data_o=8'd22 ;
        endcase
    end

endmodule


module sbox#(
    parameter DATAW = 32
    )(
    input   logic [DATAW-1:0] data_i,
    output  logic [DATAW-1:0] data_o
);

    logic [DATAW/4-1: 0]data_i_31_24, data_o_31_24;
    logic [DATAW/4-1: 0]data_i_23_16, data_o_23_16;
    logic [DATAW/4-1: 0]data_i_15_8, data_o_15_8;
    logic [DATAW/4-1: 0]data_i_7_0, data_o_7_0;

    assign data_i_31_24 = data_i[31:24];
    assign data_i_23_16 = data_i[23:16];
    assign data_i_15_8 = data_i[15:8];
    assign data_i_7_0 = data_i[7:0];

    sbox_case sbox_31_24(
        .data_i(data_i_31_24),
        .data_o(data_o_31_24)
        );

    sbox_case sbox_23_16(
        .data_i(data_i_23_16),
        .data_o(data_o_23_16)
        );

    sbox_case sbox_15_8(
        .data_i(data_i_15_8),
        .data_o(data_o_15_8)
        );
    sbox_case sbox_7_0(
        .data_i(data_i_7_0),
        .data_o(data_o_7_0)
        );

    assign data_o = {data_o_31_24, data_o_23_16, data_o_15_8, data_o_7_0};
endmodule
