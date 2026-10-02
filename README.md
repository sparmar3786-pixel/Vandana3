# Angel One + NSE-AI OI Algo Terminal (Paper signals) — v2

## 1. Backend (PC / VPS)
```
cd backend
pip install -r requirements.txt
cp .env.example .env      # apni Angel One details bharein
python server.py
```
- SmartAPI app banayein: https://smartapi.angelone.in  -> API key
- TOTP secret: Angel One par TOTP enable karte waqt milta hai
- Market hours (9:15-15:30 IST) me signals chalte hain. `data/features.csv` me features log hote hain.

## NSE AI (v2 badlav)
- `nse_client.py` nseindia.com/option-chain ka wahi JSON leta hai (option-chain-v3, fallback option-chain-indices) har NSE_POLL_SEC (60s).
- `nse_features.py`: PCR, OI change imbalance, per-strike buildup (Long/Short buildup, Short covering, Long unwinding), support/resistance (max PE/CE OI), max pain, IV skew, poll-to-poll OI momentum.
- AI trend = sirf NSE features par. Model na ho to NSE rule-trend chalta hai; `data/nse_features.csv` me log hota hai.
- Entry tabhi jab Angel live score + NSE AI dono same direction me hon aur spot support/resistance ke bilkul paas na ho. Exit: SL/Target/Angel reversal/NSE AI flip.
- NSE API unofficial hai: block/change ho sakti hai, NSE ke Terms of Use check karein, poll slow rakhein.

## Angel One SmartAPI connection (Vandana2)

The APK uses the Vandana2 backend endpoint `/v1/angel/login`. The backend follows Angel One's documented `loginByPassword` flow:

1. Client ID + PIN/MPIN + current 6-digit TOTP + SmartAPI API key.
2. Backend calls Angel One `/rest/auth/angelbroking/user/v1/loginByPassword`.
3. Backend keeps JWT, refresh token and feed token server-side.
4. REST market-data calls use the authenticated SmartConnect session.
5. SmartWebSocketV2 is started for live LTP/OI and reconnects when the socket drops.
6. Token refresh is attempted during long-running sessions; a fresh login is used when refresh is rejected.
7. Instrument-master download is independent of authentication, so a temporary master-file problem cannot turn a successful Angel login into a login failure.

No Angel password, TOTP secret, JWT, refresh token or feed token is stored in the APK. Order placement is not exposed.

Official references: https://smartapi.angelone.in/docs and https://github.com/angel-one/smartapi-python

## 2. AI model train
Kam se kam 5-10 trading din data collect hone ke baad: `python train_ai.py`  (model ban jaane par signal ke saath AI confidence aayega, low confidence par trade skip)

## 3. Android APK
```
cd flutter_app
flutter create . --platforms=android      # android folder generate
```
`android/app/src/main/AndroidManifest.xml` ke `<application` me add karein:
`android:usesCleartextTraffic="true"`  (sirf plain http ke liye; VPS par HTTPS best hai)
```
flutter build apk --release
```
APK: `build/app/outputs/flutter-apk/app-release.apk`. App me settings icon se backend URL + API_TOKEN dalein.

## Logic
Price vs OI (last LOOKBACK_SEC): Long buildup / Short covering = bullish CE; Short buildup / Long unwinding = bearish.
PUT side me direction ulta. Score = 0.5*OI + 0.3*EMA trend + 0.2*PCR. Entry ATM option, SL/Target premium % se, exit = SL/Target/reversal.

## Warning
Order placement intentionally nahi hai. Pehle paper trade + backtest karein. Profit guaranteed nahi.


Baseline: Vandana1 Build 156 process copied into Vandana2; legacy terminal implementation removed from the active source tree.
