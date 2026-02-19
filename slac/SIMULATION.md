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

## 5. 정리

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
