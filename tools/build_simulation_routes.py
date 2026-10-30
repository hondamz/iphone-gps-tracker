#!/usr/bin/env python3
"""Erzeugt GPSTracker/Resources/SimulationRoutes.json für die Simulations-Betriebsarten.

Quellen (Daten © OpenStreetMap-Mitwirkende, ODbL):
- Straßen/Fußwege: OSRM (router.project-osrm.org, routing.openstreetmap.de), inkl. Segmentdauer
  → realistische Geschwindigkeit je Abschnitt.
- Flughafen Köln/Bonn: Rollwege und Bahnen aus der OSM-API, Rollwege per Dijkstra auf dem Rollweg-Graphen.
- Wegenetz des Flughafens (Fuß/Fahrzeug/Flugzeug) innerhalb der OSM-Flughafengrenze → AirportGraph.json;
  daraus berechnet die App zur Laufzeit zufällige Strecken (Services/AirportPlanner.swift).
- Bahnstrecken: BRouter (brouter.de, Profil „rail“) mit Anfahr-/Bremsprofil; Lücke der Gleisdaten in
  Troisdorf mit OSM-Gleisen überbrückt.

Aufruf:  python3 tools/build_simulation_routes.py <cache-ordner>
Der Cache-Ordner nimmt Rohdaten auf (routes/*.json, osm/*.osm) und wird bei Bedarf befüllt.
"""
import glob, heapq, json, math, os, subprocess, sys, time, xml.etree.ElementTree as ET

CACHE = sys.argv[1] if len(sys.argv) > 1 else "build/sim-cache"
OUT = os.path.join(os.path.dirname(__file__), "..", "GPSTracker", "Resources", "SimulationRoutes.json")
OUT_GRAPH = os.path.join(os.path.dirname(__file__), "..", "GPSTracker", "Resources", "AirportGraph.json")
UA = "iphone-gps-tracker-dev"

def fetch(url, path):
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        subprocess.run(["curl", "-s", "-m", "90", "-A", UA, url, "-o", path], check=True)
        time.sleep(1.5)
    return path

def dist(a, b):
    r = 6371000.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp, dl = p2 - p1, math.radians(b[1] - a[1])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))

def osrm(name, profile, coords):
    base = ("https://router.project-osrm.org/route/v1/driving/" if profile == "car"
            else f"https://routing.openstreetmap.de/routed-{profile}/route/v1/driving/")
    path = fetch(base + coords + "?overview=full&geometries=geojson&annotations=distance,duration",
                 os.path.join(CACHE, "routes", name + ".json"))
    route = json.load(open(path))["routes"][0]
    pts = [(c[1], c[0]) for c in route["geometry"]["coordinates"]]
    durs = [d for leg in route["legs"] for d in leg["annotation"]["duration"]]
    dists = [d for leg in route["legs"] for d in leg["annotation"]["distance"]]
    speeds = [(dd / t if t > 0 else 1.0) for dd, t in zip(dists, durs)] + [0]
    return [(lat, lon, max(0.5, sp)) for (lat, lon), sp in zip(pts, speeds)]

# --- Flughafen Köln/Bonn: OSM-Daten ------------------------------------------------------
CGN_TILES = [(lon, lat) for lon in (7.105, 7.120, 7.135, 7.150, 7.165) for lat in (50.848, 50.858, 50.868, 50.878)]

def load_osm(paths):
    """Knoten, Knoten-Tags und Wege (je Weg-ID nur einmal) aus OSM-XML-Dateien."""
    nodes, ntags, ways, seen = {}, {}, [], set()
    for f in sorted(paths):
        root = ET.parse(f).getroot()
        for n in root.iter("node"):
            nodes[n.get("id")] = (float(n.get("lat")), float(n.get("lon")))
            t = {x.get("k"): x.get("v") for x in n.findall("tag")}
            if t:
                ntags[n.get("id")] = t
        for w in root.iter("way"):
            if w.get("id") in seen:
                continue
            seen.add(w.get("id"))
            ways.append(({t.get("k"): t.get("v") for t in w.findall("tag")}, [x.get("ref") for x in w.findall("nd")]))
    return nodes, ntags, ways

def cgn_osm():
    paths = [fetch(f"https://api.openstreetmap.org/api/0.6/map?bbox={lon},{lat},{round(lon + 0.015, 3)},{round(lat + 0.01, 3)}",
                   os.path.join(CACHE, "osm-cgn", f"t{i + 1}.osm")) for i, (lon, lat) in enumerate(CGN_TILES)]
    return load_osm(paths)

def cgn_graph(nodes, ways):
    """Rollweg-Graph (Rollwege, Bahnen mit Strafgewicht) für die festen Flugzeug-Abschnitte."""
    edges, runways = {}, {}
    for tags, refs in ways:
        kind = tags.get("aeroway")
        if kind not in ("taxiway", "runway"):
            continue
        if kind == "runway":
            runways.setdefault(tags.get("ref"), []).append(refs)
        penalty = 4.0 if kind == "runway" else 1.0     # Rollen bevorzugt auf Rollwegen
        for a, b in zip(refs, refs[1:]):
            if a in nodes and b in nodes:
                d = dist(nodes[a], nodes[b]) * penalty
                edges.setdefault(a, []).append((b, d))
                edges.setdefault(b, []).append((a, d))
    return edges, runways

# --- Flughafen Köln/Bonn: Wegenetz für zufällige Strecken ----------------------------------
FOOT, CAR, PLANE, STEPS, RUNWAY = 1, 2, 4, 8, 16
FOOT_HW = {"footway", "path", "pedestrian", "steps", "platform", "corridor", "service", "track",
           "living_street", "residential", "unclassified", "tertiary", "cycleway"}
CAR_HW = {"service": 7, "unclassified": 11, "tertiary": 13, "residential": 8, "track": 5,
          "trunk": 16, "trunk_link": 11, "living_street": 4}
POI_KEYS = ("aeroway", "amenity", "building", "highway", "railway", "public_transport", "tourism", "office")
POI_SKIP_AEROWAY = {"parking_position", "taxiway", "runway", "holding_position", "stopway", "aerodrome"}

def cgn_boundary():
    path = fetch("https://nominatim.openstreetmap.org/search?q=Flughafen%20K%C3%B6ln%2FBonn&format=jsonv2&limit=1&polygon_geojson=1",
                 os.path.join(CACHE, "cgn-boundary.json"))
    return json.load(open(path))[0]["geojson"]["coordinates"][0]

def point_in(poly, lat, lon):
    inside = False
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[i - 1]
        if (y1 > lat) != (y2 > lat) and lon < (x2 - x1) * (lat - y1) / (y2 - y1) + x1:
            inside = not inside
    return inside

def components(adj):
    comp, sizes = {}, []
    for n0 in adj:
        if n0 in comp:
            continue
        stack, comp[n0], count = [n0], len(sizes), 0
        while stack:
            x = stack.pop()
            count += 1
            for y in adj[x]:
                if y not in comp:
                    comp[y] = len(sizes)
                    stack.append(y)
        sizes.append(count)
    return comp, sizes

def airport_graph(nodes, ntags, ways):
    """Wegenetz innerhalb der Flughafengrenze; je Verkehrsart nur das größte zusammenhängende Teilnetz."""
    poly = cgn_boundary()
    edges = {}                                       # (a, b) -> [Maske, Kfz-Tempo m/s]
    for tags, refs in ways:
        hw, aw = tags.get("highway"), tags.get("aeroway")
        mask, speed = 0, 0
        if hw in FOOT_HW and tags.get("foot") != "no" and tags.get("access") != "no":
            mask |= FOOT | (STEPS if hw == "steps" else 0)
        if hw in CAR_HW and tags.get("motor_vehicle") != "no" and tags.get("area") != "yes":
            mask |= CAR
            speed = {"parking_aisle": 4, "driveway": 5}.get(tags.get("service"), CAR_HW[hw])
            try:
                speed = min(speed, float(tags["maxspeed"]) / 3.6)
            except (KeyError, ValueError):
                pass
        if aw in ("taxiway", "runway"):
            mask |= PLANE | (RUNWAY if aw == "runway" else 0)
        if not mask:
            continue
        for a, b in zip(refs, refs[1:]):
            if a in nodes and b in nodes and (point_in(poly, *nodes[a]) or point_in(poly, *nodes[b])):
                key = (min(a, b), max(a, b))
                m0, s0 = edges.get(key, (0, 0))
                edges[key] = (m0 | mask, max(s0, speed))
    # kleine Teilnetze je Verkehrsart verwerfen
    for bit in (FOOT, CAR, PLANE):
        adj = {}
        for (a, b), (m, _) in edges.items():
            if m & bit:
                adj.setdefault(a, []).append(b)
                adj.setdefault(b, []).append(a)
        comp, sizes = components(adj)
        big = max(range(len(sizes)), key=lambda i: sizes[i])
        for key, (m, sp) in list(edges.items()):
            if m & bit and comp[key[0]] != big:
                m &= ~bit
                if bit == FOOT:
                    m &= ~STEPS
                if bit == PLANE:
                    m &= ~RUNWAY
                edges[key] = (m, sp)
    edges = {k: v for k, v in edges.items() if v[0] & (FOOT | CAR | PLANE)}
    used = sorted({n for k in edges for n in k}, key=lambda n: nodes[n])
    index = {n: i for i, n in enumerate(used)}
    # benannte Ziele (für Streckennamen in der App)
    pois, names = [], set()
    def add_poi(name, lat, lon):
        if name and name not in names and point_in(poly, lat, lon):
            names.add(name)
            pois.append([name, round(lat, 6), round(lon, 6)])
    for tags, refs in ways:
        if "name" in tags and any(k in tags for k in POI_KEYS) and tags.get("aeroway") not in POI_SKIP_AEROWAY \
                and tags.get("highway") in (None, "platform"):
            pts = [nodes[r] for r in refs if r in nodes]
            if pts:
                add_poi(tags["name"], sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
    for nid, tags in ntags.items():
        if "name" in tags and (tags.get("railway") == "station" or tags.get("aeroway") in ("gate", "helipad")
                               or tags.get("amenity") in ("parking", "bus_station", "fuel", "fire_station")):
            add_poi(tags["name"], *nodes[nid])
    return {
        "attribution": "Kartendaten © OpenStreetMap-Mitwirkende (ODbL)",
        "masks": {"foot": FOOT, "car": CAR, "plane": PLANE, "steps": STEPS, "runway": RUNWAY},
        "nodes": [[round(nodes[n][0], 6), round(nodes[n][1], 6)] for n in used],
        "edges": [[index[a], index[b], m, round(sp, 1)] for (a, b), (m, sp) in edges.items()],
        "pois": pois,
    }

# --- Bahnstrecken (BRouter) und Ausflüge nach Köln/Bonn ------------------------------------
def rail_line(name, lonlats):
    path = fetch(f"https://brouter.de/brouter?lonlats={lonlats}&profile=rail&alternativeidx=0&format=geojson",
                 os.path.join(CACHE, "routes", name + ".geojson"))
    feature = json.load(open(path))["features"][0]
    return [(c[1], c[0]) for c in feature["geometry"]["coordinates"]]

def along_pt(p, q, f):
    return (p[0] + (q[0] - p[0]) * f, p[1] + (q[1] - p[1]) * f)

def train(pts, vmax, accel=0.6, vmin=2.0):
    """Anfahr-/Bremsprofil zwischen zwei Halten: v = min(vmax, √(2·a·s_Start), √(2·a·s_Ziel))."""
    dense = [pts[0]]                       # höchstens 40 m Punktabstand, damit das Bremsen greift
    for p, q in zip(pts, pts[1:]):
        n = max(1, math.ceil(dist(p, q) / 40))
        dense += [along_pt(p, q, k / n) for k in range(1, n + 1)]
    pts = dense
    along = [0.0]
    for p, q in zip(pts, pts[1:]):
        along.append(along[-1] + dist(p, q))
    total = along[-1]
    return [(lat, lon, max(vmin, min(vmax, math.sqrt(2 * accel * s), math.sqrt(2 * accel * (total - s)))))
            for (lat, lon), s in zip(pts, along)]

TROISDORF = (50.81395, 7.15087)
TROISDORF_SUED = (50.8105999, 7.1580828)   # erster Punkt der rechten Rheinstrecke, den BRouter findet

def troisdorf_bridge():
    """Gleisweg vom Bahnhof Troisdorf zur rechten Rheinstrecke (in BRouter fehlt dort ein Stück)."""
    tiles = ["7.145,50.795,7.1535,50.806", "7.1535,50.795,7.162,50.806",
             "7.145,50.806,7.1535,50.817", "7.1535,50.806,7.162,50.817"]
    nodes, _, ways = load_osm([fetch(f"https://api.openstreetmap.org/api/0.6/map?bbox={b}",
                                     os.path.join(CACHE, "osm-troisdorf", f"t{i + 1}.osm")) for i, b in enumerate(tiles)])
    adj = {}
    for tags, refs in ways:
        if tags.get("railway") == "rail":
            refs = [r for r in refs if r in nodes]
            for a, b in zip(refs, refs[1:]):
                d = dist(nodes[a], nodes[b])
                adj.setdefault(a, []).append((b, d))
                adj.setdefault(b, []).append((a, d))
    comp, _ = components({n: [m for m, _ in v] for n, v in adj.items()})
    start = min(adj, key=lambda n: dist(nodes[n], TROISDORF))
    target = min(adj, key=lambda n: dist(nodes[n], TROISDORF_SUED))
    a, b = min(((x, y) for x in adj if comp[x] == comp[start] for y in adj if comp[y] == comp[target]),
               key=lambda p: dist(nodes[p[0]], nodes[p[1]]))
    gap = dist(nodes[a], nodes[b])
    assert gap < 200, f"Lücke Troisdorf zu groß: {gap:.0f} m"
    return dijkstra(nodes, adj, start, a) + [nodes[b]]

def reverse(points):
    """Strecke rückwärts; Tempo je Abschnitt bleibt dem Abschnitt zugeordnet."""
    pts = list(reversed(points))
    speeds = [p[2] for p in points]
    rs = list(reversed(speeds[:-1])) + [0]
    return [(lat, lon, sp) for (lat, lon, _), sp in zip(pts, rs)]

CGN_T1 = (50.87871, 7.12267)       # Terminal 1, Vorfahrt
CGN_BF = (50.87908, 7.11936)       # Bahnhof Köln/Bonn Flughafen
KOELN_HBF, KOELN_DEUTZ = (50.94278, 6.95907), (50.94170, 6.97382)
KOELN_VORPLATZ = (50.94240, 6.95830)
BONN_MARKT, BEUEL, MENDEN = (50.73533, 7.10224), (50.73853, 7.12746), (50.77968, 7.14958)

def ll(*pts):
    return "|".join(f"{lon},{lat}" for lat, lon in pts)

def osrm_ll(*pts):
    return ";".join(f"{lon},{lat}" for lat, lon in pts)

def city_trips(add):
    """Ausflüge vom Flughafen nach Köln/Bonn (Auto oder Bahn), jeweils mit Stadtrundgang und Rückweg."""
    # Köln – Auto
    add("koeln_auto_hin", "Ausflug Köln: Auto Flughafen → Dom", osrm("koeln_auto_hin", "car", osrm_ll(CGN_T1, KOELN_VORPLATZ)), 120)
    add("koeln_rundgang", "Ausflug Köln: Rundgang Dom, Altstadt, Rheinufer",
        osrm("koeln_rundgang", "foot", osrm_ll(KOELN_VORPLATZ, (50.94130, 6.95814), (50.93610, 6.96050),
                                               (50.93800, 6.96320), (50.93800, 6.95900), (50.93660, 6.95450),
                                               KOELN_VORPLATZ)), 90)
    add("koeln_auto_zurueck", "Ausflug Köln: Auto Dom → Flughafen", osrm("koeln_auto_zurueck", "car", osrm_ll(KOELN_VORPLATZ, CGN_T1)), 120)
    # Köln – Bahn (S-Bahn/RE über Messe/Deutz)
    add("koeln_bahn_1", "Ausflug Köln: Bahn Flughafen → Köln Messe/Deutz", train(rail_line("koeln_bahn_1", ll(CGN_BF, KOELN_DEUTZ)), 25), 50)
    add("koeln_bahn_2", "Ausflug Köln: Bahn Messe/Deutz → Köln Hbf", train(rail_line("koeln_bahn_2", ll(KOELN_DEUTZ, KOELN_HBF)), 16), 60)
    add("koeln_bahn_3", "Ausflug Köln: Bahn Köln Hbf → Messe/Deutz", train(rail_line("koeln_bahn_3", ll(KOELN_HBF, KOELN_DEUTZ)), 16), 50)
    add("koeln_bahn_4", "Ausflug Köln: Bahn Messe/Deutz → Flughafen", train(rail_line("koeln_bahn_4", ll(KOELN_DEUTZ, CGN_BF)), 25), 90)
    # Bonn – Auto
    add("bonn_auto_hin", "Ausflug Bonn: Auto Flughafen → Markt", osrm("bonn_auto_hin", "car", osrm_ll(CGN_T1, BONN_MARKT)), 120)
    add("bonn_rundgang", "Ausflug Bonn: Rundgang Markt, Münster, Hofgarten, Rhein",
        osrm("bonn_rundgang", "foot", osrm_ll(BONN_MARKT, (50.73450, 7.09990), (50.73300, 7.10350),
                                              (50.73550, 7.10770), BONN_MARKT)), 90)
    add("bonn_auto_zurueck", "Ausflug Bonn: Auto Markt → Flughafen", osrm("bonn_auto_zurueck", "car", osrm_ll(BONN_MARKT, CGN_T1)), 120)
    # Bonn – Bahn: S-Bahn bis Troisdorf, Umstieg, RE über die rechte Rheinstrecke nach Bonn-Beuel
    bridge = troisdorf_bridge()
    sued = rail_line("bonn_bahn_menden", ll(bridge[-1], MENDEN))
    to_beuel = train(rail_line("bonn_bahn_beuel", ll(MENDEN, BEUEL)), 25)
    to_menden = train(bridge + sued[1:], 28)
    add("bonn_bahn_1", "Ausflug Bonn: S-Bahn Flughafen → Troisdorf", train(rail_line("bonn_bahn_troisdorf", ll(CGN_BF, TROISDORF)), 25), 240)
    add("bonn_bahn_2", "Ausflug Bonn: RE Troisdorf → Menden", to_menden, 40)
    add("bonn_bahn_3", "Ausflug Bonn: RE Menden → Bonn-Beuel", to_beuel, 60)
    add("bonn_beuel_rundgang", "Ausflug Bonn: zu Fuß Beuel → Kennedybrücke → Markt → Münster und zurück",
        osrm("bonn_beuel_rundgang", "foot", osrm_ll(BEUEL, (50.73950, 7.11300), BONN_MARKT, (50.73450, 7.09990),
                                                    BONN_MARKT, BEUEL)), 90)
    add("bonn_bahn_4", "Ausflug Bonn: RE Bonn-Beuel → Menden", reverse(to_beuel), 40)
    add("bonn_bahn_5", "Ausflug Bonn: RE Menden → Troisdorf", reverse(to_menden), 240)
    add("bonn_bahn_6", "Ausflug Bonn: S-Bahn Troisdorf → Flughafen",
        train(list(reversed(rail_line("bonn_bahn_troisdorf", ll(CGN_BF, TROISDORF)))), 25), 90)
    return [
        {"id": "koeln_auto", "name": "Ausflug Köln (Auto)", "start": list(CGN_T1), "startMode": "car",
         "routes": ["koeln_auto_hin", "koeln_rundgang", "koeln_auto_zurueck"]},
        {"id": "koeln_bahn", "name": "Ausflug Köln (Bahn)", "start": list(CGN_BF), "startMode": "foot",
         "routes": ["koeln_bahn_1", "koeln_bahn_2", "koeln_rundgang", "koeln_bahn_3", "koeln_bahn_4"]},
        {"id": "bonn_auto", "name": "Ausflug Bonn (Auto)", "start": list(CGN_T1), "startMode": "car",
         "routes": ["bonn_auto_hin", "bonn_rundgang", "bonn_auto_zurueck"]},
        {"id": "bonn_bahn", "name": "Ausflug Bonn (Bahn)", "start": list(CGN_BF), "startMode": "foot",
         "routes": ["bonn_bahn_1", "bonn_bahn_2", "bonn_bahn_3", "bonn_beuel_rundgang", "bonn_bahn_4", "bonn_bahn_5", "bonn_bahn_6"]},
    ]

def nearest(nodes, edges, p):
    return min((n for n in edges), key=lambda n: dist(nodes[n], p))

def dijkstra(nodes, edges, start, goal):
    best, prev, queue = {start: 0.0}, {}, [(0.0, start)]
    while queue:
        d, n = heapq.heappop(queue)
        if n == goal:
            break
        if d > best.get(n, 1e18):
            continue
        for m, w in edges[n]:
            nd = d + w
            if nd < best.get(m, 1e18):
                best[m], prev[m] = nd, n
                heapq.heappush(queue, (nd, m))
    path = [goal]
    while path[-1] != start:
        path.append(prev[path[-1]])
    return [nodes[n] for n in reversed(path)]

def taxi(nodes, edges, a, b, speed):
    pts = dijkstra(nodes, edges, nearest(nodes, edges, a), nearest(nodes, edges, b))
    return [(lat, lon, speed) for lat, lon in pts]

def along(p, q, frac):
    return (p[0] + (q[0] - p[0]) * frac, p[1] + (q[1] - p[1]) * frac)

def runway_roll(a, b, length, v0, v1, step=50.0):
    """Gerader Lauf von a Richtung b über `length` m, Geschwindigkeit linear v0 → v1."""
    total = dist(a, b)
    n = max(2, int(length / step))
    return [(*along(a, b, (length * k / n) / total), v0 + (v1 - v0) * k / n) for k in range(n + 1)]

def compact(points):
    """Punkte enger als 2 m zusammenfassen, Werte runden."""
    out = []
    for i, (lat, lon, sp) in enumerate(points):
        if out and dist(out[-1][:2], (lat, lon)) < 2:
            if i == len(points) - 1:          # Endpunkt (Tempo 0) nie verschlucken
                out[-1] = (round(lat, 6), round(lon, 6), 0.0)
            continue
        out.append((round(lat, 6), round(lon, 6), round(sp, 1)))
    return [list(p) for p in out]

# --- Deutschland: Ortsnetz für zufällige Fahrten -------------------------------------------
# Orte je Region (Koordinaten aus OSM/Nominatim, offensichtliche Fehltreffer von Hand korrigiert)
DE_HUBS = [
    ("mz_hbf", "Mainz Hbf", "mainz", 50.00111, 8.25872),
    ("mz_dom", "Mainzer Dom", "mainz", 49.99888, 8.27383),
    ("mz_uni", "Uni Mainz", "mainz", 49.99204, 8.23711),
    ("mz_gonsenheim", "Mainz-Gonsenheim", "mainz", 49.99774, 8.21431),
    ("mz_bretzenheim", "Mainz-Bretzenheim", "mainz", 49.98250, 8.24650),
    ("mz_mombach", "Mainz-Mombach", "mainz", 50.02280, 8.22934),
    ("mz_hechtsheim", "Mainz-Hechtsheim", "mainz", 49.96050, 8.27952),
    ("mz_laubenheim", "Mainz-Laubenheim", "mainz", 49.96155, 8.31077),
    ("mz_finthen", "Mainz-Finthen", "mainz", 49.98050, 8.17200),
    ("mz_zollhafen", "Zollhafen Mainz", "mainz", 50.01570, 8.25832),
    ("mz_kastel", "Mainz-Kastel", "mainz", 50.00834, 8.28444),
    ("wi_hbf", "Wiesbaden Hbf", "mainz", 50.06983, 8.24398),
    ("pb_hbf", "Paderborn Hbf", "paderborn", 51.71286, 8.74044),
    ("pb_dom", "Paderborner Dom", "paderborn", 51.71870, 8.75500),
    ("pb_uni", "Uni Paderborn", "paderborn", 51.70752, 8.77241),
    ("pb_neuhaus", "Schloss Neuhaus", "paderborn", 51.74540, 8.71720),
    ("pb_borchen", "Borchen", "paderborn", 51.66105, 8.72315),
    ("pb_elsen", "Paderborn-Elsen", "paderborn", 51.73000, 8.69300),
    ("pb_wewer", "Paderborn-Wewer", "paderborn", 51.68028, 8.68634),
    ("pb_flughafen", "Flughafen Paderborn/Lippstadt", "paderborn", 51.61054, 8.62056),
    ("pb_marienloh", "Marienloh", "paderborn", 51.76527, 8.78826),
    ("pb_lippspringe", "Bad Lippspringe", "paderborn", 51.78330, 8.81667),
    ("pb_salzkotten", "Salzkotten", "paderborn", 51.67176, 8.60686),
    ("k_dom", "Kölner Dom", "koelnbonn", 50.94130, 6.95814),
    ("k_deutz", "Köln Messe/Deutz", "koelnbonn", 50.94099, 6.97513),
    ("bn_markt", "Bonn Markt", "koelnbonn", 50.73533, 7.10224),
]
# Fernstrecken zwischen den Regionen (je Richtung nutzbar, Rückweg = umgekehrte Strecke)
DE_LONG = [("mz_hbf", "pb_hbf"), ("mz_hbf", "k_deutz"), ("k_deutz", "pb_hbf"), ("bn_markt", "mz_hbf")]
DE_WALK_MAX = 2500      # Fußwege zwischen Orten bis zu dieser Luftlinie (m)

def thin(points, spacing=20.0):
    """Punkte enger als `spacing` zusammenfassen; Tempo = Strecke / Fahrzeit der zusammengefassten Abschnitte."""
    out = [list(points[0])]
    acc_d = acc_t = 0.0
    for (lat, lon, sp), nxt in zip(points, points[1:]):
        d = dist((lat, lon), nxt[:2])
        acc_d += d
        acc_t += d / max(sp, 0.5)
        if acc_d >= spacing or nxt is points[-1]:
            out[-1][2] = acc_d / acc_t if acc_t > 0 else 0
            out.append([nxt[0], nxt[1], 0.0])
            acc_d = acc_t = 0.0
    return out

def germany_network(add):
    """Routen zwischen allen Orten einer Region (Auto, nahe Orte auch zu Fuß) und Fernstrecken."""
    hubs = {h[0]: h for h in DE_HUBS}
    links = []
    def link(a, b, mode):
        rid = f"de_{a}_{b}_{mode}"
        (_, na, _, la, lo), (_, nb, _, lb, lob) = hubs[a], hubs[b]
        pts = osrm(rid, "car" if mode == "car" else "foot", f"{lo},{la};{lob},{lb}")
        add(rid, f"{na} → {nb}", thin(pts, 25 if mode == "car" else 10), 0)
        links.append({"from": a, "to": b, "route": rid, "mode": mode})
    ids = [h[0] for h in DE_HUBS]
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            if hubs[a][2] != hubs[b][2]:
                continue
            link(a, b, "car")
            if dist(hubs[a][3:], hubs[b][3:]) <= DE_WALK_MAX:
                link(a, b, "foot")
    for a, b in DE_LONG:
        link(a, b, "car")
    return {
        "hubs": [{"id": i, "name": n, "region": r, "lat": la, "lon": lo} for i, n, r, la, lo in DE_HUBS],
        "links": links,
    }

def main():
    routes = []
    def add(rid, name, pts, pause=0):
        routes.append({"id": rid, "name": name, "pauseAfterSeconds": pause, "points": compact(pts)})

    # Deutschland: Ortsnetz Mainz/Wiesbaden, Paderborn/Borchen, Köln/Bonn mit Fernstrecken
    # (ersetzt seit 0.8.0 die feste Schleife Mainz → Paderborn → Köln/Bonn → Mainz)
    germany = germany_network(add)

    # Flughafen Köln/Bonn – feste Flugzeug-Abschnitte (Start/Landung) und Fußweg
    nodes, ntags, ways = cgn_osm()
    edges, runways = cgn_graph(nodes, ways)
    rw = runways["13L/31R"][0]
    thr13l, thr31r = nodes[rw[0]], nodes[rw[-1]]
    stand_c = (50.8795, 7.1245)       # Vorfeld C am Terminal 1
    cargo_w = (50.8682, 7.1298)       # Vorfeld W (Fracht)
    add("cgn_walk", "Fußweg Bahnhof → Terminal 1 → Terminal 2",
        osrm("cgn_walk", "foot", "7.11936,50.87908;7.12267,50.87871;7.11907,50.88082;7.11936,50.87908"), 60)
    taxi_out = taxi(nodes, edges, stand_c, thr13l, 8.0)
    taxi_out[:3] = [(lat, lon, 1.5) for lat, lon, _ in taxi_out[:3]]          # Pushback
    add("cgn_taxi_out", "Rollen Vorfeld C → Bahn 13L", taxi_out, 30)
    add("cgn_takeoff", "Startlauf Bahn 13L", runway_roll(thr13l, thr31r, 1700, 2.0, 80.0), 420)
    landing = runway_roll(thr31r, thr13l, 1900, 70.0, 12.0)
    add("cgn_landing", "Landung Bahn 31R und Rollen zum Vorfeld W",
        landing + taxi(nodes, edges, landing[-1][:2], cargo_w, 8.0), 180)
    add("cgn_taxi_back", "Rollen Vorfeld W → Vorfeld C", taxi(nodes, edges, cargo_w, stand_c, 7.0), 120)

    trips = city_trips(add)
    graph = airport_graph(nodes, ntags, ways)
    json.dump(graph, open(OUT_GRAPH, "w"), separators=(",", ":"))

    data = {
        "attribution": "Kartendaten © OpenStreetMap-Mitwirkende (ODbL); Routen mit OSRM und BRouter berechnet",
        "cityTrips": trips,
        "germany": germany,
        "modes": {
            # Rückfallebene, falls die App das Ortsnetz nicht lesen kann
            "germany": ["de_mz_hbf_mz_dom_car", "de_mz_hbf_pb_hbf_car", "de_pb_hbf_pb_borchen_car"],
            "cgnAirport": ["cgn_walk", "cgn_taxi_out", "cgn_takeoff", "cgn_landing", "cgn_taxi_back"],
        },
        "routes": routes,
    }
    json.dump(data, open(OUT, "w"), separators=(",", ":"))
    for r in routes:
        length = sum(dist(a[:2], b[:2]) for a, b in zip(r["points"], r["points"][1:]))
        dur = sum(dist(a[:2], b[:2]) / max(a[2], 0.5) for a, b in zip(r["points"], r["points"][1:]))
        print(f'{r["id"]:16} {len(r["points"]):5} Pkt {length/1000:7.1f} km {dur/60:6.0f} min')
    print("→", os.path.normpath(OUT), os.path.getsize(OUT) // 1024, "KB")
    print("→", os.path.normpath(OUT_GRAPH), os.path.getsize(OUT_GRAPH) // 1024, "KB:",
          len(graph["nodes"]), "Knoten,", len(graph["edges"]), "Kanten,", len(graph["pois"]), "Ziele")

if __name__ == "__main__":
    main()
