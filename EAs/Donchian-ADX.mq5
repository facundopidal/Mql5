//+------------------------------------------------------------------+
//|                                                 Donchain-ADX.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>

//Inputs

input group "Indicadores";
input int donchian_period = 20; //Periodo Donchain
input int adx_period = 14; // Periodo ADX
input int fast_atr_period = 5; // Periodo ATR Rápido
input int slow_atr_period = 28; // Periodo ATR Lento

input group "Riesgo";
input int atr_period = 14; // Periodo ATR SL-TP
input double atrs_sl = 1; // Cantidad de ATRs para SL
input double atrs_tp = 2; // Cantidad de ATRs para TPs
input bool trailing_flag = true; // Activar Trailing Stop
input double partial_close_tp = 0.5; // Cierre Parcial
input double trailing_stop = 0.01; // Porcentaje Trailing Stop

input group "Tamaño de la posición"
input double riesgo = 0.005; // Riesgo
input double lotes_min = 0.01; // Lotaje Minimo

input group "Filtros";
input int adx_param = 25; // Parámetro ADX
input int adx_count = 10; // Racha de ADX
input int first_hour = 10; // Primer Horario
input int second_hour = 21; // Segundo Horario
input int cant_candles = 8; // Cantidad de velas sin operar


//Handlers

int adx_h;
int atr_h;
int f_atr_h;
int s_atr_h;

//Buffers

double highs[];
double lows[];
double adx[];
double atr[];
double f_atr[];
double s_atr[];
MqlRates candles[];

//Variables
CTrade trade;
ulong trade_ticket;
bool time_passed = true;
double lotaje;

int OnInit() {
   
   adx_h = iADX(_Symbol, PERIOD_CURRENT, adx_period);
   atr_h = iATR(_Symbol, PERIOD_CURRENT, atr_period);
   f_atr_h = iATR(_Symbol, PERIOD_CURRENT, fast_atr_period);
   s_atr_h = iATR(_Symbol, PERIOD_CURRENT, slow_atr_period);
   
   ArraySetAsSeries(candles, true);
   
   return(INIT_SUCCEEDED);
}


void OnTick() {

   //------------Manejar Operaciones----------------
   
   GestionarTakeProfit();
   
   GestionarTrailingStop();
   
   if(!PositionSelectByTicket(trade_ticket) && trade_ticket != 0) {
      trade_ticket = 0;
      EmpezarTemporizador();
   }

   //------------Indicadores--------------------
   
   CopyBuffer(adx_h, 0, 1, adx_count, adx);   
   CopyBuffer(atr_h, 0, 1, 1, atr);
   CopyBuffer(f_atr_h, 0, 1, 1, f_atr);
   CopyBuffer(s_atr_h, 0, 1, 1, s_atr);
   CopyHigh(_Symbol, PERIOD_CURRENT, 2, donchian_period, highs);
   CopyLow(_Symbol, PERIOD_CURRENT, 2, donchian_period, lows);
   CopyRates(_Symbol, PERIOD_CURRENT, 1, donchian_period, candles);
   
   DibujarCanalDonchian();
   
   //------------Filtros--------------------
   
   if(!AdxAlcista(adx) || f_atr[0] <= s_atr[0] || trade_ticket > 0) return;
   
   MqlDateTime time = {};
   TimeCurrent(time);
   
   if(!HorarioValido(time.hour) || !time_passed) return; 
   
   
   //------------Entradas--------------------
   
   int donchian_high = ArrayMaximum(highs, 0, donchian_period);
   int donchian_low = ArrayMinimum(lows, 0, donchian_period);
   
   if(ObtenerUltimoCierre() > highs[donchian_high]) {
      EjecutarCompra();
   } 
   else if(ObtenerUltimoCierre() < lows[donchian_low]) {
      EjecutarVenta();
   }
   else {
      Print("NO HAY OPERACION PORQUE NO SALIO DEL CANAL");
   }
}

void OnTimer() {
   time_passed = true;
}

void EjecutarCompra() {
   double Ask = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
   
   if(trailing_flag) {
      trade.Buy(CalcularLotes(), _Symbol, Ask, Ask - atrs_sl * atr[0], 0, "SUPER MEGA LONG");
   } else {
      trade.Buy(CalcularLotes(), _Symbol, Ask, Ask - atrs_sl * atr[0], Ask + atrs_tp * atr[0], "SUPER MEGA LONG");
   }
   
   trade_ticket = trade.ResultOrder();
}

void EjecutarVenta() {
   double Bid = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
   if(trailing_flag) {
      trade.Sell(CalcularLotes(), _Symbol, Bid, Bid + atrs_sl * atr[0], 0, "SUPER MEGA SHORT");
   } else {
      trade.Sell(CalcularLotes(), _Symbol, Bid, Bid + atrs_sl * atr[0], Bid - atrs_tp * atr[0], "SUPER MEGA SHORT");
   }
   
   trade_ticket = trade.ResultOrder();
}

void GestionarTakeProfit() {
    if (PositionSelectByTicket(trade_ticket) && trailing_flag) {
        double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE) PositionGetInteger(POSITION_TYPE);
        double current_price = SymbolInfoDouble(_Symbol, (type == POSITION_TYPE_BUY) ? SYMBOL_BID : SYMBOL_ASK);
        double tp_parcial = (type == POSITION_TYPE_BUY) ? entry_price + atrs_tp * atr[0] : entry_price - atrs_tp * atr[0];

        if ((type == POSITION_TYPE_BUY && current_price >= tp_parcial) ||
            (type == POSITION_TYPE_SELL && current_price <= tp_parcial)) {
            
            trade.PositionClosePartial(trade_ticket, lotaje * partial_close_tp);
            Print(partial_close_tp * 100, "% de la posición cerrada en TP Parcial.");
        }
    }
}

void GestionarTrailingStop() {
    if (PositionSelectByTicket(trade_ticket) && trailing_flag) {
        double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE) PositionGetInteger(POSITION_TYPE);
        double current_price = SymbolInfoDouble(_Symbol, (type == POSITION_TYPE_BUY) ? SYMBOL_BID : SYMBOL_ASK);
        double new_sl = (type == POSITION_TYPE_BUY) ? current_price - (current_price * trailing_stop) : current_price + (current_price * trailing_stop);

        if ((type == POSITION_TYPE_BUY && new_sl > PositionGetDouble(POSITION_SL)) ||
            (type == POSITION_TYPE_SELL && new_sl < PositionGetDouble(POSITION_SL))) {
            
            trade.PositionModify(trade_ticket, new_sl, PositionGetDouble(POSITION_TP));
            Print("Trailing Stop ajustado.");
        }
    }
}

double ObtenerUltimoCierre() {
    double close_price[];  // Array para almacenar los precios de cierre

    // Copiar el último precio de cierre (vela anterior)
    if (CopyClose(_Symbol, PERIOD_CURRENT, 1, 1, close_price) <= 0) {
        Print("Error al obtener el precio de cierre");
        return 0.0;  // Devolver 0 si hay error
    }
    return close_price[0];  // Retornar el último precio de cierre
}

bool AdxAlcista(double &adx_values[]) {
   for(uint i = adx_values.Size() - 2; i <= 0; i--) {
      Print("DEBUG-Size: ", adx_values.Size(), "Index: ", i);
      if(adx_values[i] <= adx_values[i+1]) return false;
   }
   
   return adx[0] > adx_param;
}

bool HorarioValido(int time) {
   return time >= first_hour && time <= second_hour;
}
void DibujarCanalDonchian() {
    static datetime last_update = 0;

    // Obtener el tiempo de la última vela
    datetime time_buffer[];
    if (CopyTime(_Symbol, PERIOD_CURRENT, 0, donchian_period + 2, time_buffer) <= 0) {
        Print("❌ Error al obtener tiempos de velas.");
        return;
    }

    // Si la última actualización es la misma que la última vela, salir
    if (last_update == time_buffer[0]) {
        Print("⏩ Ya se actualizó en esta vela, no se redibuja.");
        return;
    }
    last_update = time_buffer[0];

    // Obtener los valores de Donchian
    if (CopyHigh(_Symbol, PERIOD_CURRENT, 2, donchian_period, highs) <= 0 ||
        CopyLow(_Symbol, PERIOD_CURRENT, 2, donchian_period, lows) <= 0) {
        Print("❌ Error al copiar datos de Donchian.");
        return;
    }

    int donchian_high_index = ArrayMaximum(highs, 0, donchian_period);
    int donchian_low_index = ArrayMinimum(lows, 0, donchian_period);
    double donchian_high = highs[donchian_high_index];
    double donchian_low = lows[donchian_low_index];

    // 🔍 Depuración: Imprimimos los valores obtenidos
    Print("📊 Donchian High: ", donchian_high, " | Donchian Low: ", donchian_low);

    datetime time_start = time_buffer[donchian_period + 1]; // Vela más antigua
    datetime time_end = time_buffer[0];                     // Vela más reciente

    // 🗑 Eliminar líneas existentes antes de redibujar
    ObjectDelete(0, "Donchian_High");
    ObjectDelete(0, "Donchian_Low");

    // 🎨 Dibujar la línea superior
    if (!ObjectCreate(0, "Donchian_High", OBJ_TREND, 0, time_start, donchian_high, time_end, donchian_high)) {
        Print("❌ Error al crear Donchian_High");
    }
    ObjectSetInteger(0, "Donchian_High", OBJPROP_COLOR, clrBlueViolet);
    ObjectSetInteger(0, "Donchian_High", OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, "Donchian_High", OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, "Donchian_High", OBJPROP_RAY_RIGHT, false);
    ObjectMove(0, "Donchian_High", 0, time_start, donchian_high);
    ObjectMove(0, "Donchian_High", 1, time_end, donchian_high);

    // 🎨 Dibujar la línea inferior
    if (!ObjectCreate(0, "Donchian_Low", OBJ_TREND, 0, time_start, donchian_low, time_end, donchian_low)) {
        Print("❌ Error al crear Donchian_Low");
    }
    ObjectSetInteger(0, "Donchian_Low", OBJPROP_COLOR, clrBlueViolet);
    ObjectSetInteger(0, "Donchian_Low", OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, "Donchian_Low", OBJPROP_WIDTH, 2);
    ObjectSetInteger(0, "Donchian_Low", OBJPROP_RAY_RIGHT, false);
    ObjectMove(0, "Donchian_Low", 0, time_start, donchian_low);
    ObjectMove(0, "Donchian_Low", 1, time_end, donchian_low);
}

void EmpezarTemporizador() {
   time_passed = false;
   EventSetTimer(PeriodSeconds() * cant_candles);
}

double CalcularLotes() {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double max_risk = equity * riesgo;
   double atr_stop_loss = atrs_sl * atr[0];
   double position_size = 0;
//---------------------------------ESTO ES UNA GRAN MENTIRA-------------------------------------

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

// Calcular el lotaje permitido: se divide el riesgo máximo (en dinero) entre el riesgo por lote
// y se ajusta dividiendo entre el tamaño del contrato.
   double lotaje_permitido = NormalizeDouble((max_risk / (atr_stop_loss / tick_size)) / tick_value, _Digits);
   //double lotaje_permitido = NormalizeDouble(max_risk / ((atr_stop_loss / tick_size) * tick_value), _Digits);
   
   
   lotaje = lotaje_permitido < lotes_min ? lotes_min : lotaje_permitido;
   
   
   return lotaje;
}