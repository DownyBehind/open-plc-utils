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

### 5.3 다른 SLAC 메시지의 전체 바이트 수 (헤더 19바이트 + payload)

| 메시지 | payload 크기(대략) | 전체(대략) |
|--------|--------------------|------------|
| CM_SLAC_PARAM.REQ | 1+1+8+1+2 = 13 | 32 |
| CM_SLAC_PARAM.CNF | 6+1+1+1+6+1+1+8+2 = 27 | 46 |
| CM_START_ATTEN_CHAR.IND | 2+1+1+1+6+8 = 19 | 38 |
| CM_ATTEN_CHAR.IND | 2+6+8+17+17+1+(1+255) | 306+ |
| CM_SLAC_MATCH.REQ | 2+2+17+6+17+6+8+8 = 66 | 85 |
| CM_SLAC_MATCH.CNF | 2+2+17+6+17+6+8+8+7+1+16 = 90 | 109 |
| CM_SET_KEY.REQ | 41 | **60** |
| CM_SET_KEY.CNF | 1+4+4+1+2+1+1+27 = 41 | 60 |

정확한 필드 정의는 `slac/slac.h`의 `cm_slac_param_request`, `cm_slac_match_request` 등 구조체를 보면 바이트 단위로 맞출 수 있습니다.

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

**요약:** `slac-sim-veth.sh start` → `run` 또는 `run-capture`(또는 pev/evse 수동 실행)로 시뮬레이션하고, `slac-sim-watch.sh` 또는 tcpdump로 **ether proto 0x88e1** 트래픽을 보면 EV와 EVSE가 주고받는 메시지를 **MAC Layer(PLC 레벨)** 에서 관측할 수 있습니다.
