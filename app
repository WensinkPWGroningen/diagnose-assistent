import streamlit as st
import requests
import re

st.set_page_config(
    page_title="Wensink Mercedes Diagnose Assistent",
    page_icon="🚘",
    layout="wide"
)

# ============================================================
# BEVEILIGING WENSINK DIAGNOSE ASSISTENT
# ============================================================

def controleer_toegang():
    if "ingelogd" not in st.session_state:
        st.session_state["ingelogd"] = False

    if not st.session_state["ingelogd"]:
        st.markdown("<h1>🔒 Wensink Diagnose Assistent</h1>", unsafe_allow_html=True)
        st.write("Voer de gezamenlijke toegangscode in.")

        ingevoerde_code = st.text_input(
            "Toegangscode",
            type="password",
            key="toegangscode_invoer"
        )

        if st.button("INLOGGEN", use_container_width=True):
            try:
                juiste_code = st.secrets["password"]["code"]
            except Exception:
                juiste_code = "wensink2026" # Fallback indien secrets lokaal ontbreken

            if ingevoerde_code == juiste_code:
                st.session_state["ingelogd"] = True
                st.rerun()
            else:
                st.error("Onjuiste toegangscode.")
        st.stop()

controleer_toegang()

# ============================================================
# INITIALISATIE SESSION STATE VARIABELEN
# ============================================================
if "chat_history" not in st.session_state:
    st.session_state["chat_history"] = []
if "laatste_diagnose" not in st.session_state:
    st.session_state["laatste_diagnose"] = ""
if "rdw_kenteken" not in st.session_state:
    st.session_state["rdw_kenteken"] = ""

# ============================================================
# RESETFUNCTIES VOOR NIEUWE DIAGNOSE
# ============================================================

def reset_nieuw_voertuig():
    sleutels = [
        "rdw_model", "rdw_jaar", "rdw_motor", "rdw_handelsbenaming", "rdw_kenteken",
        "kenteken_invoer", "kilometerstand", "foutcode", "klacht", "extra_info", 
        "laatste_diagnose", "diagnose_chat_input"
    ]
    for sleutel in sleutels:
        st.session_state[sleutel] = ""
    st.session_state["chat_history"] = []
    st.session_state["reset_melding"] = "Nieuw voertuig: alle gegevens zijn gewist."

def reset_zelfde_voertuig():
    sleutels = [
        "kilometerstand", "foutcode", "klacht", "extra_info", "laatste_diagnose", "diagnose_chat_input"
    ]
    for sleutel in sleutels:
        st.session_state[sleutel] = ""
    st.session_state["chat_history"] = []
    st.session_state["reset_melding"] = "Nieuwe diagnose gestart voor hetzelfde voertuig."

# ============================================================
# WENSINK HUISSTIJL & STYLING
# ============================================================

st.markdown("""
<style>
    .stApp { background-color: #f4f6f9; }
    .main-title { color: #111827; font-size: 28px; font-weight: 800; margin-top: 5px; }
    .subtitle { color: #64748b; font-size: 14px; margin-bottom: 20px; }
    .stButton button { background-color: #111827; color: white; border-radius: 8px; font-weight: bold; min-height: 45px; }
    .stButton button:hover { background-color: #374151; color: white; border-color: #374151; }
    .vehicle-card { background: white; padding: 18px; border-radius: 10px; border: 1px solid #e2e8f0; margin-bottom: 20px; font-size: 15px; box-shadow: 0 1px 3px rgba(0,0,0,0.05); }
</style>
""", unsafe_allow_html=True)

st.markdown("<h1 class='main-title'>🚘 Wensink Mercedes-Benz Werkplaats Assistent</h1>", unsafe_allow_html=True)
st.markdown("<p class='subtitle'>Snelle voertuigidentificatie en storingsanalyse voor de werkplaats.</p>", unsafe_allow_html=True)

# Resetknoppen bovenin
col_reset1, col_reset2 = st.columns(2)
with col_reset1:
    if st.button("♻️ NIEUW VOERTUIG STARTEN", use_container_width=True):
        reset_nieuw_voertuig()
        st.rerun()
with col_reset2:
    if st.button("🔄 NIEUWE DIAGNOSE (ZELFDE AUTO)", use_container_width=True):
        reset_zelfde_voertuig()
        st.rerun()

if "reset_melding" in st.session_state and st.session_state["reset_melding"]:
    st.success(st.session_state["reset_melding"])
    st.session_state["reset_melding"] = ""

st.divider()

# ============================================================
# RDW API CONFIGURATIE & OPHALEN
# ============================================================

RDW_VOERTUIG_URL = "https://opendata.rdw.nl/resource/m9d7-ebf2.json"
RDW_BRANDSTOF_URL = "https://opendata.rdw.nl/resource/8ysn-digu.json"

def haal_rdw_data(kenteken):
    kenteken = re.sub(r"[^A-Z0-9]", "", kenteken.upper())
    if not kenteken:
        return None

    headers = {"Accept": "application/json", "User-Agent": "Wensink-Diagnose-Assistent/1.0"}

    try:
        response = requests.get(RDW_VOERTUIG_URL, params={"kenteken": kenteken, "$limit": 1}, headers=headers, timeout=10)
        response.raise_for_status()
        voertuigen = response.json()

        if not voertuigen:
            return None
        voertuig = voertuigen[0]

        merk = voertuig.get("merk", "").strip().upper()
        if merk not in ("MERCEDES-BENZ", "MERCEDES BENZ"):
            return "GEEN_MERCEDES"

        brandstof_response = requests.get(RDW_BRANDSTOF_URL, params={"kenteken": kenteken, "$limit": 5}, headers=headers, timeout=10)
        brandstof_response.raise_for_status()
        brandstof_data = brandstof_response.json()

        brandstoffen = [item.get("brandstof_omschrijving", "").upper() for item in brandstof_data]
        heeft_elektrisch = any("ELEKTR" in b for b in brandstoffen)
        heeft_benzine = any("BENZINE" in b for b in brandstoffen)
        heeft_diesel = any("DIESEL" in b for b in brandstoffen)

        if heeft_elektrisch and (heeft_benzine or heeft_diesel):
            brandstof = "Hybride (PHEV/HEV)"
        elif heeft_elektrisch:
            brandstof = "Elektrisch (EV)"
        elif heeft_benzine:
            brandstof = "Benzine"
        elif heeft_diesel:
            brandstof = "Diesel"
        elif brandstoffen:
            brandstof = brandstoffen[0].title()
        else:
            brandstof = "Onbekend"

        ruwe_model = voertuig.get("handelsbenaming", "Onbekend").strip().upper()
        model_regels = [
            ("SPRINTER", "Sprinter"), ("VITO", "Vito"), ("GLA", "GLA"), ("GLB", "GLB"),
            ("GLC", "GLC"), ("GLE", "GLE"), ("GLS", "GLS"), ("CLA", "CLA"), ("CLS", "CLS"),
            ("EQS", "EQS"), ("EQE", "EQE"), ("EQB", "EQB"), ("EQA", "EQA"), ("SLK", "SLK"),
            ("S-KLASSE", "S-Klasse"), ("E-KLASSE", "E-Klasse"), ("C-KLASSE", "C-Klasse"),
            ("A-KLASSE", "A-Klasse"), ("B-KLASSE", "B-Klasse"), ("AMG GT", "AMG GT")
        ]

        schoon_model = ruwe_model.title()
        for zoekterm, modelnaam in model_regels:
            if zoekterm in ruwe_model:
                schoon_model = modelnaam
                break

        datum = str(voertuig.get("datum_eerste_toelating", ""))
        bouwjaar = datum[:4] if len(datum) >= 4 else "Onbekend"

        return {
            "kenteken": kenteken,
            "merk": merk,
            "model": schoon_model,
            "handelsbenaming": ruwe_model,
            "jaar": bouwjaar,
            "motor": brandstof
        }
    except Exception:
        return None

# Kenteken Invoer
kenteken_invoer = st.text_input("Kenteken invoeren (bijv. AB123CD)", key="kenteken_invoer")

if kenteken_invoer:
    with st.spinner("Voertuiggegevens ophalen bij RDW..."):
        voertuig_data = haal_rdw_data(kenteken_invoer)
        if voertuig_data and voertuig_data != "GEEN_MERCEDES":
            st.session_state["rdw_kenteken"] = voertuig_data["kenteken"]
            st.session_state["rdw_model"] = voertuig_data["model"]
            st.session_state["rdw_jaar"] = voertuig_data["jaar"]
            st.session_state["rdw_motor"] = voertuig_data["motor"]
            st.session_state["rdw_handelsbenaming"] = voertuig_data["handelsbenaming"]
        elif voertuig_data == "GEEN_MERCEDES":
            st.error("⚠️ Dit voertuig is geen Mercedes-Benz. De assistent ondersteunt uitsluitend Mercedes-Benz voertuigen.")
            st.session_state["rdw_kenteken"] = ""
        else:
            st.warning("Kenteken niet gevonden in de RDW-database. Controleer het kenteken.")

if st.session_state.get("rdw_kenteken"):
    st.markdown(f"""
    <div class='vehicle-card'>
        <strong>🚗 Geregistreerd Voertuig:</strong> Mercedes-Benz {st.session_state['rdw_model']}<br>
        <small><strong>Handelsbenaming:</strong> {st.session_state['rdw_handelsbenaming']} | <strong>Bouwjaar:</strong> {st.session_state['rdw_jaar']} | <strong>Aandrijving:</strong> {st.session_state['rdw_motor']} | <strong>Kenteken:</strong> {st.session_state['rdw_kenteken']}</small>
    </div>
    """, unsafe_allow_html=True)

# ============================================================
# WERKPLAATS INVOERGEGEVENS
# ============================================================
st.write("### 🛠️ Diagnose Gegevens")
col1, col2 = st.columns(2)

with col1:
    kilometerstand = st.text_input("Kilometerstand (km)", key="kilometerstand")
    foutcode = st.text_input("Actieve storingscodes / DTC's (bijv. P0299, P0101, C2205)", key="foutcode")

with col2:
    klacht = st.text_area("Klachtomschrijving / Symptomen", key="klacht")
    extra_info = st.text_area("Extra parameters / Live data / Uitgevoerde tests", key="extra_info")

# ============================================================
# MASTER TECHNICIAN ANALYSE STARTEN
# ============================================================

GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

def get_api_key():
    try:
        return st.secrets["GOOGLE_API_KEY"]
    except Exception:
        return ""

if st.session_state.get("rdw_kenteken"):
    if st.button("🔥 START MASTER TECHNICIAN ANALYSE", use_container_width=True):
        if not klacht and not foutcode:
            st.warning("Voer minimaal een klachtomschrijving of storingscode in om de analyse te starten.")
        else:
            api_key = get_api_key()
            if not api_key:
                st.error("GOOGLE_API_KEY ontbreekt in de Streamlit secrets.")
                st.stop()

            with st.spinner("De Wensink Diagnose Assistent analyseert XENTRY-gegevens en fabriekslogica..."):
                try:
                    systeem_prompt = """Je bent de ervaren Mercedes-Benz Master Technician van de Wensink Diagnose Assistent. 
Je ondersteunt monteurs in de werkplaats met praktijkgerichte, logische en technische diagnoses.
Geef gestructureerd advies:
1. Mogelijke oorzaken (van meest waarschijnlijk naar complex).
2. XENTRY teststappen / actuele meetwaarden om te controleren.
3. Specifieke aandachtspunten / TIPS / bekende coulance- of servicerecomes voor dit model."""

                    gebruikers_prompt = f"""
Voertuig Context:
- Model: {st.session_state.get('rdw_model')}
- Handelsbenaming: {st.session_state.get('rdw_handelsbenaming')}
- Bouwjaar: {st.session_state.get('rdw_jaar')}
- Motorisering: {st.session_state.get('rdw_motor')}

Werkplaats Input:
- Kilometerstand: {kilometerstand if kilometerstand else 'Niet opgegeven'}
- Storingscodes (DTC): {foutcode if foutcode else 'Geen'}
- Klachtomschrijving: {klacht if klacht else 'Geen'}
- Extra info / Metingen: {extra_info if extra_info else 'Geen'}
"""

                    headers = {"Content-Type": "application/json", "x-goog-api-key": api_key}
                    payload = {
                        "system_instruction": {"parts": [{"text": systeem_prompt}]},
                        "contents": [{"role": "user", "parts": [{"text": gebruikers_prompt}]}],
                        "generationConfig": {"temperature": 0.2}
                    }

                    response = requests.post(GEMINI_API_URL, json=payload, headers=headers, timeout=60)
                    response.raise_for_status()
                    
                    antwoord = response.json()["candidates"][0]["content"]["parts"][0]["text"]

                    st.session_state["laatste_diagnose"] = antwoord
                    st.session_state["chat_history"] = [
                        {"role": "user", "parts": [{"text": gebruikers_prompt}]},
                        {"role": "model", "parts": [{"text": antwoord}]}
                    ]
                    st.rerun()

                except Exception as e:
                    st.error(f"Fout tijdens genereren van diagnose: {str(e)}")

# TOON DIAGNOSE RAPPORT
if st.session_state.get("laatste_diagnose"):
    st.markdown("### 📋 Officiële Wensink Diagnose Rapportage")
    st.info(st.session_state["laatste_diagnose"])

# ============================================================
# VERVOLGCHAT LOGICA & UI
# ============================================================

if st.session_state.get("laatste_diagnose"):
    st.divider()
    st.subheader("💬 Verdieping & Vervolgvragen")
    st.write("Stel gerust aanvullende vragen (bijv. over aanhaalmomenten, pin-bezetting of extra meetwaarden).")

    # Toon chat geschiedenis
    for bericht in st.session_state["chat_history"][2:]:
        rol = "user" if bericht["role"] == "user" else "assistant"
        with st.chat_message(rol):
            parts = bericht.get("parts", [])
            if parts:
                st.markdown(parts[0].get("text", ""))

    nieuwe_vraag = st.chat_input("Stel een vervolgvraag...", key="diagnose_chat_input")

    if nieuwe_vraag:
        with st.chat_message("user"):
            st.markdown(nieuwe_vraag)

        with st.spinner("Bezig met ophalen technische verdieping..."):
            try:
                api_key = get_api_key()
                systeem_prompt = "Je bent de Mercedes-Benz Master Technician van de Wensink Diagnose Assistent. Beantwoord de vervolgvraag to-the-point en technisch accuraat."

                inhoud = []
                for b in st.session_state["chat_history"]:
                    inhoud.append({"role": b["role"], "parts": [{"text": b["parts"][0]["text"]}]})
                
                inhoud.append({"role": "user", "parts": [{"text": nieuwe_vraag}]})

                headers = {"Content-Type": "application/json", "x-goog-api-key": api_key}
                payload = {
                    "system_instruction": {"parts": [{"text": systeem_prompt}]},
                    "contents": inhoud,
                    "generationConfig": {"temperature": 0.2}
                }

                resp = requests.post(GEMINI_API_URL, json=payload, headers=headers, timeout=60)
                resp.raise_for_status()
                antwoord_tekst = resp.json()["candidates"][0]["content"]["parts"][0]["text"]

                st.session_state["chat_history"].extend([
                    {"role": "user", "parts": [{"text": nieuwe_vraag}]},
                    {"role": "model", "parts": [{"text": antwoord_tekst}]}
                ]))
                st.rerun()

            except Exception as e:
                st.error(f"Fout bij ophalen vervolgantwoord: {str(e)}")
