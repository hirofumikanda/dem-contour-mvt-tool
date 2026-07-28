import * as maplibreglExports from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import workerUrl from "maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url";
import { Protocol } from "pmtiles";
import "./maplibre-gl-compare.css";

import contoursStyle from "./styles/contours.json";
import gsiStdStyle from "./styles/gsi_std.json";

// maplibre-gl v6 only has named exports (no default export), but
// maplibre-gl-compare.js is vendored from hirofumikanda/maplibre-swipe as a
// plain script that attaches itself to a global `maplibregl` object by
// assigning `maplibregl.Compare = ...`. A `import * as` namespace object is
// read-only, so copy the exports into a plain mutable object first.
const maplibregl = { ...maplibreglExports };
window.maplibregl = maplibregl;

// Vite's bundler can't reliably resolve maplibre-gl's worker file on its
// own; it must be pointed at explicitly (see maplibre-gl-js Vite bundler docs).
maplibregl.setWorkerUrl(workerUrl);

const protocol = new Protocol();
maplibregl.addProtocol("pmtiles", protocol.tile);

await import("./maplibre-gl-compare.js");

// build/contours.pmtiles data range (see `pmtiles show build/contours.pmtiles`).
const CENTER = [138.065186, 35.362176];
const ZOOM = 14;

const beforeMap = new maplibregl.Map({
  container: "before",
  style: contoursStyle,
  center: CENTER,
  zoom: ZOOM,
  hash: true,
});

const afterMap = new maplibregl.Map({
  container: "after",
  style: gsiStdStyle,
  center: CENTER,
  zoom: ZOOM,
});

const container = "#comparison-container";

new maplibregl.Compare(beforeMap, afterMap, container, {});

afterMap.on("load", () => {
  afterMap.addControl(new maplibregl.NavigationControl());
});

function setupContextMenuHandler(map) {
  map.on("contextmenu", (e) => {
    const features = map.queryRenderedFeatures(e.point);
    resetHighlightLayers(map);

    if (features.length > 0) {
      console.log("フィーチャ数：" + features.length);
      for (const feature of features) {
        console.log("レイヤーID：" + feature.layer.id);
        console.log("フィーチャID：" + feature.id);
        console.log(JSON.stringify(feature.properties, null, 2));
      }

      const lineFeatures = features.filter(
        (f) => "layer" in f && f.layer.type === "line",
      );
      if (lineFeatures.length > 0) {
        map.getSource("highlight-source-line").setData({
          type: "FeatureCollection",
          features: lineFeatures,
        });
      }

      const fillFeatures = features.filter(
        (f) =>
          "layer" in f && f.layer.type === "fill" && f.layer.id !== "land",
      );
      if (fillFeatures.length > 0) {
        map.getSource("highlight-source-fill").setData({
          type: "FeatureCollection",
          features: fillFeatures,
        });
      }
    }
  });
}

function resetHighlightLayers(map) {
  // Line layer
  if (map.getSource("highlight-source-line")) {
    map.removeLayer("highlight-layer-line");
    map.removeSource("highlight-source-line");
  }
  map.addSource("highlight-source-line", {
    type: "geojson",
    data: {
      type: "FeatureCollection",
      features: [],
    },
  });
  map.addLayer({
    id: "highlight-layer-line",
    type: "line",
    source: "highlight-source-line",
    paint: {
      "line-color": "rgb(255, 0, 0)",
      "line-width": 2,
      "line-opacity": 0.8,
    },
  });

  // Fill layer
  if (map.getSource("highlight-source-fill")) {
    map.removeLayer("highlight-layer-fill");
    map.removeSource("highlight-source-fill");
  }
  map.addSource("highlight-source-fill", {
    type: "geojson",
    data: {
      type: "FeatureCollection",
      features: [],
    },
  });
  map.addLayer({
    id: "highlight-layer-fill",
    type: "fill",
    source: "highlight-source-fill",
    paint: {
      "fill-outline-color": "rgb(255, 0, 0)",
    },
  });
}

setupContextMenuHandler(beforeMap);
setupContextMenuHandler(afterMap);
