# SLAC 시퀀스 PC 시뮬레이션 (Linux, MAC Layer 관측)

PLC 보드(IC) 없이 Linux PC에서 EV(pev)와 EVSE(evse)가 주고받는 **SLAC 메시지를 MAC Layer(PLC 레벨)** 에서 관측하는 방법입니다.

## 요구사항

- Linux (veth 지원)
- `ip` (iproute2), `tcpdump`
- open-plc-utils 빌드: **프로젝트 루트에서** `make -C slac` 실행 후 `slac/evse`, `slac/pev` 생성됨 (설치 불필요)

## 1. veth 시뮬레이션 환경 준비

EV와 EVSE가 통신할 가상 이더넷 쌍을 만듭니다.

```bash
# 프로젝트 루트에서
sudo ./scripts/slac-sim-veth.sh start
```

인터페이스 `veth_pev`(EV용), `veth_evse`(EVSE용)가 생성되고 서로 연결됩니다.

## 2. SLAC 시퀀스 실행

### 방법 A: 한 터미널에서 한 번에 실행

```bash
sudo ./scripts/slac-sim-veth.sh run
```

evse가 백그라운드로 뜨고, 이어서 pev가 실행되어 SLAC 파라미터 → 매칭 → 충전 시뮬레이션까지 진행됩니다.

### 방법 B: 터미널 두 개로 분리 실행 (메시지 관측용)

**프로젝트 루트**에서 실행 (evse/pev는 PATH에 없으면 `slac/` 안 바이너리 사용).

**터미널 1 (EVSE):**
```bash
sudo ./slac/evse -i veth_evse -v
```

**터미널 2 (EV):**
```bash
sudo ./slac/pev -i veth_pev -v
```

또는 `cd slac` 한 뒤 `sudo ./evse -i veth_evse -v`, `sudo ./pev -i veth_pev -v`.

이렇게 하면 터미널 3에서 아래처럼 MAC 레벨 트래픽을 볼 수 있습니다.

## 3. MAC Layer(PLC 레벨) 메시지 관측

SLAC 메시지는 **Ethernet EtherType 0x88E1 (HomePlug AV)** 로 전송됩니다. 아래 중 하나로 관측하면 됩니다.

### 3.1 실시간 화면 출력 (다른 터미널에서)

```bash
sudo ./scripts/slac-sim-watch.sh
```

또는 직접 tcpdump:

```bash
sudo tcpdump -i veth_pev -e -XX ether proto 0x88e1
```

- `-e`: 이더넷 헤더(출발/목적 MAC 등) 출력  
- `-XX`: 페이로드 hex+ASCII 덤프  
- 프레임마다 **ODA/OSA(MAC)** 와 **HomePlug MME**(CM_SLAC_PARAM, CM_ATTEN_CHAR, CM_SLAC_MATCH 등) 내용을 확인할 수 있습니다.

### 3.2 pcap 파일로 저장 후 분석

시뮬레이션을 돌리면서 MAC 레벨 트래픽을 파일로 남기려면:

```bash
sudo ./scripts/slac-sim-veth.sh run-capture
```

기본 저장 위치: 현재 디렉터리, 파일명 `slac_mac_YYYYMMDD_HHMMSS.pcap`.  
다른 디렉터리를 쓰려면:

```bash
SLAC_CAP_DIR=/tmp/slac_caps sudo ./scripts/slac-sim-veth.sh run-capture
```

저장된 pcap 확인:

```bash
tcpdump -r slac_mac_*.pcap -e -XX ether proto 0x88e1
```

Wireshark에서 열면 EtherType 0x88e1로 필터링해 EV–EVSE 간 SLAC 메시지 흐름을 볼 수 있습니다.

## 4. MAC Layer에서 보이는 SLAC 메시지 개요

| MME (MMTYPE)        | 방향 예시        | 설명 |
|---------------------|------------------|------|
| CM_SLAC_PARAM       | REQ(PEV→) / CNF(←EVSE) | 파라미터 협상 |
| CM_START_ATTEN_CHAR | IND(PEV→)        | 감쇠 측정 시작 |
| CM_MNBC_SOUND       | IND(PEV→)        | 사운드 |
| CM_ATTEN_CHAR       | IND(PEV→) / RSP(←EVSE) | 감쇠 프로파일 |
| CM_SLAC_MATCH       | REQ(PEV→EVSE) / CNF(←EVSE) | PEV–EVSE 매칭 |
| CM_SET_KEY          | REQ/CNF           | 키 설정 (호스트→**로컬 PLC 칩**) |

프레임 구조: **Ethernet(14) + MMV(1) + MMTYPE(2) + payload**.  
MMTYPE 정의는 `mme/homeplug.h` (CM_SLAC_PARAM 0x6064, CM_SLAC_MATCH 0x607C 등) 참고.

### 4.1 veth 시뮬에서 "Can't set key"가 나오는 이유

**SLAC 시퀀스(CM_SLAC_PARAM → … → CM_SLAC_MATCH)는 veth에서 정상 완료됩니다.**  
그 다음 단계인 **CM_SET_KEY**는 실제 환경에서 **호스트가 자신 쪽 PLC 칩(QCA7000 등)에게** NMK/NID를 설정하라고 보내는 명령입니다. 즉, PEV는 PEV-PLC에게, EVSE는 EVSE-PLC에게 보내고, **응답(CNF)은 같은 기기(로컬 칩)에서 옵니다.**

veth 시뮬에는 PLC 칩이 없고, 채널이 곧 상대편(pev↔evse)이라:

- pev가 보낸 CM_SET_KEY.REQ → evse에게 전달됨 (evse는 CNF를 기대하므로 "REQ ?" 로 표시)
- evse가 보낸 CM_SET_KEY.REQ → pev에게 전달됨 (pev는 CNF를 기대하므로 "CNF ?" 등으로 표시)

그래서 **"Can't set key"는 veth만 쓰는 시뮬에서는 예상되는 결과**이며, SLAC 매칭과 MAC 레벨 메시지 관측 목적에는 문제 없습니다.

## 5. MAC Layer 패킷: 전체 바이트 수 및 바이트별 의미

**네, 볼 수 있습니다.** tcpdump `-XX`(또는 Wireshark)로 캡처한 hex 덤프의 각 바이트는 코드의 구조체와 1:1로 대응됩니다.

### 5.1 공통 프레임 구조 (모든 SLAC 메시지)

| 오프셋(바이트) | 크기 | 필드 | 의미 |
|----------------|------|------|------|
| 0   | 6 | ODA | 목적지 MAC (Destination) |
| 6   | 6 | OSA | 출발지 MAC (Source) |
| 12  | 2 | MTYPE | EtherType, **0x88E1** (HomePlug AV), 네트워크 바이트 순서 |
| 14  | 1 | MMV | MME Version (0x01) |
| 15  | 2 | MMTYPE | 메시지 타입(하위 2비트: Req=0/Cnf=1/Ind=2/Rsp=3), 리틀 엔디언 |
| 17  | 1 | FMSN | Fragment Sequence Number |
| 18  | 1 | FMID | Fragment ID |
| 19~ | 가변 | payload | MME별 페이로드 |

- **공통 헤더만:** 14(Ethernet) + 5(HomePlug FMI) = **19바이트**.  
- **전체 패킷 길이** = 19 + (해당 MME payload 길이).  
- MMTYPE 예: CM_SLAC_PARAM\|REQ = 0x6064, CM_SLAC_MATCH\|CNF = 0x607D, CM_SET_KEY\|REQ = 0x6008.

### 5.2 예: CM_SET_KEY.REQ — 전체 60바이트

아래는 **CM_SET_KEY.REQ** 한 개의 전체 길이와, 오프셋별로 어떤 필드인지입니다 (코드: `slac/pev_cm_set_key.c`, `slac.h` 상의 상수).

| 오프셋 | 크기 | 필드 | 의미 |
|--------|------|------|------|
| 0  | 6 | ODA | 목적지 MAC |
| 6  | 6 | OSA | 출발지 MAC |
| 12 | 2 | MTYPE | 0x88E1 |
| 14 | 1 | MMV | 0x01 |
| 15 | 2 | MMTYPE | 0x6008 (CM_SET_KEY\|REQ), 리틀엔디언이면 08 60 |
| 17 | 1 | FMSN | |
| 18 | 1 | FMID | |
| 19 | 1 | KEYTYPE | 0x01 |
| 20 | 4 | MYNOUNCE | 0xAAAAAAAA 등 |
| 24 | 4 | YOURNOUNCE | 0x00000000 |
| 28 | 1 | PID | 0x04 |
| 29 | 2 | PRN | 리틀엔디언 |
| 31 | 1 | PMN | 0x00 |
| 32 | 1 | CCOCAP | 0x00 |
| 33 | 7 | NID | 7바이트 NID |
| 40 | 1 | NEWEKS | 0x01 |
| 41 | 16 | NEWKEY | 16바이트 NMK |
| 57 | 3 | RSVD | 예약(0) |

실제 캡처(pev 쪽) 예:

```
00 01 02 03 04 05 | 06 07 08 09 0a 0b | 0c 0d | 0e 0f 10 11 12 | 13 14 15 16 17 18 | ...
ODA (6)          | OSA (6)          | MTYPE | MMV MMTYPE FMSN FMID | KEYTYPE MYNOUNCE ...
```

- **전체 패킷 = 60바이트** (19 + 41 payload).

### 5.3 메시지별 전체 크기 및 payload 필드 (바이트별)

아래는 **공통 헤더 19바이트(오프셋 0~18)** 뒤, 각 메시지의 **payload(오프셋 19~)** 필드 레이아웃입니다. 오프셋은 **패킷 처음(0) 기준** 바이트 위치입니다.

---

#### CM_SLAC_PARAM.REQ — 전체 32바이트

| 오프셋 | 크기 | 필드 | 의미 |
|--------|------|------|------|
| 0~18 | 19 | (공통 헤더) | ODA, OSA, MTYPE 0x88E1, MMV, MMTYPE(0x6064), FMSN, FMID |
| 19 | 1 | APPLICATION_TYPE | 0x00 등 |
| 20 | 1 | SECURITY_TYPE | 0x00 |
| 21 | 8 | RunID | SLAC_RUNID_LEN |
| 29 | 1 | CipherSuiteSetSize | |
| 30 | 2 | CipherSuite[0] | 리틀엔디언 |

---

#### CM_SLAC_PARAM.CNF — 전체 46바이트

| 오프셋 | 크기 | 필드 | 의미 |
|--------|------|------|------|
| 0~18 | 19 | (공통 헤더) | MMTYPE = 0x6065 (CNF) |
| 19 | 6 | MSOUND_TARGET | MAC 주소 |
| 25 | 1 | NUM_SOUNDS | |
| 26 | 1 | TIME_OUT | |
| 27 | 1 | RESP_TYPE | |
| 28 | 6 | FORWARDING_STA | MAC |
| 34 | 1 | APPLICATION_TYPE | |
| 35 | 1 | SECURITY_TYPE | |
| 36 | 8 | RunID | |
| 44 | 2 | CipherSuite | 리틀엔디언 |

---

#### CM_START_ATTEN_CHAR.IND — 전체 38바이트

| 오프셋 | 크기 | 필드 | 의미 |
|--------|------|------|------|
| 0~18 | 19 | (공통 헤더) | MMTYPE = 0x606A (IND) |
| 19 | 1 | APPLICATION_TYPE | |
| 20 | 1 | SECURITY_TYPE | |
| 21 | 1 | ACVarField.NUM_SOUNDS | |
| 22 | 1 | ACVarField.TIME_OUT | |
| 23 | 1 | ACVarField.RESP_TYPE | |
| 24 | 6 | ACVarField.FORWARDING_STA | MAC |
| 30 | 8 | ACVarField.RunID | |

---

#### CM_START_ATTEN_CHAR.RSP — 전체 19바이트

| 오프셋 | 크기 | 필드 | 의미 |
|--------|------|------|------|
| 0~18 | 19 | (공통 헤더만) | MMTYPE = 0x606B (RSP), payload 없음 |

---

#### CM_MNBC_SOUND.IND — 전체 71바이트

| 오프셋 | 크기 | 필드 | 의미 |
|--------|------|------|------|
| 0~18 | 19 | (공통 헤더) | MMTYPE = 0x6076 (IND) |
| 19 | 1 | APPLICATION_TYPE | |
| 20 | 1 | SECURITY_TYPE | |
| 21 | 17 | MSVarField.SenderID | SLAC_UNIQUE_ID_LEN |
| 38 | 1 | MSVarField.CNT | |
| 39 | 8 | MSVarField.RunID | |
| 47 | 8 | MSVarField.RSVD | 예약 |
| 55 | 16 | MSVarField.RND | SLAC_RND_LEN |

---

#### CM_ATTEN_CHAR.IND — 전체 326바이트

| 오프셋 | 크기 | 필드 | 의미 |
|--------|------|------|------|
| 0~18 | 19 | (공통 헤더) | MMTYPE = 0x606E (IND) |
| 19 | 1 | APPLICATION_TYPE | |
| 20 | 1 | SECURITY_TYPE | |
| 21 | 6 | ACVarField.SOURCE_ADDRESS | MAC |
| 27 | 8 | ACVarField.RunID | |
| 35 | 17 | ACVarField.SOURCE_ID | |
| 52 | 17 | ACVarField.RESP_ID | |
| 69 | 1 | ACVarField.NUM_SOUNDS | |
| 70 | 1 | ATTEN_PROFILE.NumGroups | |
| 71 | 255 | ATTEN_PROFILE.AAG | 감쇠 그룹 데이터 |

---

#### CM_ATTEN_CHAR.RSP — 전체 70바이트

| 오프셋 | 크기 | 필드 | 의미 |
|--------|------|------|------|
| 0~18 | 19 | (공통 헤더) | MMTYPE = 0x606F (RSP) |
| 19 | 1 | APPLICATION_TYPE | |
| 20 | 1 | SECURITY_TYPE | |
| 21 | 6 | ACVarField.SOURCE_ADDRESS | MAC |
| 27 | 8 | ACVarField.RunID | |
| 35 | 17 | ACVarField.SOURCE_ID | |
| 52 | 17 | ACVarField.RESP_ID | |
| 69 | 1 | ACVarField.Result | |

---

#### CM_SLAC_MATCH.REQ — 전체 85바이트

| 오프셋 | 크기 | 필드 | 의미 |
|--------|------|------|------|
| 0~18 | 19 | (공통 헤더) | MMTYPE = 0x607C (REQ) |
| 19 | 1 | APPLICATION_TYPE | |
| 20 | 1 | SECURITY_TYPE | |
| 21 | 2 | MVFLength | 리틀엔디언 |
| 23 | 17 | MatchVarField.PEV_ID | |
| 40 | 6 | MatchVarField.PEV_MAC | MAC |
| 46 | 17 | MatchVarField.EVSE_ID | |
| 63 | 6 | MatchVarField.EVSE_MAC | MAC |
| 69 | 8 | MatchVarField.RunID | |
| 77 | 8 | MatchVarField.RSVD | 예약 |

---

#### CM_SLAC_MATCH.CNF — 전체 109바이트

| 오프셋 | 크기 | 필드 | 의미 |
|--------|------|------|------|
| 0~18 | 19 | (공통 헤더) | MMTYPE = 0x607D (CNF) |
| 19 | 1 | APPLICATION_TYPE | |
| 20 | 1 | SECURITY_TYPE | |
| 21 | 2 | MVFLength | 리틀엔디언 |
| 23 | 17 | MatchVarField.PEV_ID | |
| 40 | 6 | MatchVarField.PEV_MAC | MAC |
| 46 | 17 | MatchVarField.EVSE_ID | |
| 63 | 6 | MatchVarField.EVSE_MAC | MAC |
| 69 | 8 | MatchVarField.RunID | |
| 77 | 8 | MatchVarField.RSVD1 | 예약 |
| 85 | 7 | MatchVarField.NID | SLAC_NID_LEN |
| 92 | 1 | MatchVarField.RSVD2 | 예약 |
| 93 | 16 | MatchVarField.NMK | SLAC_NMK_LEN |

---

#### CM_SET_KEY.REQ — 전체 60바이트

위 **5.2** 표와 동일. (KEYTYPE, MYNOUNCE, YOURNOUNCE, PID, PRN, PMN, CCOCAP, NID, NEWEKS, NEWKEY, RSVD.)

---

#### CM_SET_KEY.CNF — 전체 60바이트

| 오프셋 | 크기 | 필드 | 의미 |
|--------|------|------|------|
| 0~18 | 19 | (공통 헤더) | MMTYPE = 0x6009 (CNF) |
| 19 | 1 | RESULT | 결과 코드 |
| 20 | 4 | MYNOUNCE | |
| 24 | 4 | YOURNOUNCE | |
| 28 | 1 | PID | |
| 29 | 2 | PRN | 리틀엔디언 |
| 31 | 1 | PMN | |
| 32 | 1 | CCOCAP | |
| 33 | 27 | RSVD | 예약 |

---

#### CM_VALIDATE.REQ — 전체 22바이트

| 오프셋 | 크기 | 필드 | 의미 |
|--------|------|------|------|
| 0~18 | 19 | (공통 헤더) | MMTYPE = 0x6078 (REQ) |
| 19 | 1 | SignalType | |
| 20 | 1 | VRVarField.Timer | |
| 21 | 1 | VRVarField.Result | |

---

#### CM_VALIDATE.CNF — 전체 22바이트

| 오프셋 | 크기 | 필드 | 의미 |
|--------|------|------|------|
| 0~18 | 19 | (공통 헤더) | MMTYPE = 0x6079 (CNF) |
| 19 | 1 | SignalType | |
| 20 | 1 | VCVarField.ToggleNum | |
| 21 | 1 | VCVarField.Result | |

---

#### CM_ATTEN_PROFILE.IND — 전체 282바이트

| 오프셋 | 크기 | 필드 | 의미 |
|--------|------|------|------|
| 0~18 | 19 | (공통 헤더) | MMTYPE = 0x6086 (IND) |
| 19 | 6 | PEV_MAC | MAC |
| 25 | 1 | NumGroups | |
| 26 | 1 | RSVD | 예약 |
| 27 | 255 | AAG | 감쇠 데이터 |

---

**요약:** 공통 헤더 19바이트(0~18)는 항상 동일하고, **오프셋 19부터가 메시지별 payload**이며 위 표대로 바이트/필드가 대응됩니다. 구조체 정의는 `slac/slac.h` 참고.

### 5.4 어떻게 보나

- **실시간 hex:**  
  `sudo tcpdump -i veth_pev -XX ether proto 0x88e1`  
  → 각 패킷이 위 오프셋대로 나오므로, 0~13번째 바이트가 Ethernet, 14~18이 HomePlug FMI, 19부터가 payload입니다.
- **저장 후 분석:**  
  `tcpdump -r slac_mac_*.pcap -e -XX ether proto 0x88e1`  
  또는 Wireshark에서 0x88e1 필터 후 hex dump로 동일하게 바이트별로 볼 수 있습니다.
- **비트/바이트 의미 매핑:**  
  코드에서 `struct` 정의와 동일한 순서로 전송되므로, `slac/slac.h`, `mme/mme.h`, `mme/homeplug.h`의 구조체와 위 표를 같이 보면 **각 바이트/필드가 무엇을 의미하는지** 정확히 대응됩니다.

## 6. 정리

시뮬 종료 후 veth 제거:

```bash
sudo ./scripts/slac-sim-veth.sh stop
```

상태 확인:

```bash
./scripts/slac-sim-veth.sh status
```

---

## Reference (사양)

이 시뮬레이션 및 SLAC/HomePlug Green PHY 동작의 구체적인 사양 레퍼런스는 아래와 같습니다 (open-plc-utils `pev.1` / `evse.1` REFERENCES 기준).

| 구분 | 문서명 |
|------|--------|
| **프로토콜 사양** | **HomePlug Green PHY Specification, Release Version 1.1** — SLAC(Signal Level Attenuation Characterization), GreenPPEA(Green PHY PEV-EVSE Association) 메시지·시퀀스 정의. HomePlug Alliance. |
| **구현/칩셋** | **Qualcomm Atheros AR7420, QCA6410 IEEE 1901, HomePlug AV and QCA7000 HomePlug Green PHY PLC Chipset Programmer's Guide** — QCA7000 등 칩셋 MME, Host-PLC 인터페이스, CM_* 메시지 형식 등. Qualcomm (Atheros). |

- MME 타입·필드 상세: 위 **HomePlug Green PHY Specification** 및 **QCA7000 Programmer's Guide** 참조.
- 코드 내 구조체 정의: `slac/slac.h`, `mme/homeplug.h`, `mme/mme.h`.

---

**요약:** `slac-sim-veth.sh start` → `run` 또는 `run-capture`(또는 pev/evse 수동 실행)로 시뮬레이션하고, `slac-sim-watch.sh` 또는 tcpdump로 **ether proto 0x88e1** 트래픽을 보면 EV와 EVSE가 주고받는 메시지를 **MAC Layer(PLC 레벨)** 에서 관측할 수 있습니다.
