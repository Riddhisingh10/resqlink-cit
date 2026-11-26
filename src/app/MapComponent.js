'use client';
import { useEffect, useRef } from 'react';

export default function MapComponent({
  lat,
  lng,
  name,
  centerLat,
  centerLng,
  disasterLocation,
  fitBoundsLocations = false,
  requests,
  volunteers,
  onMapClick,
  selectedLocation,
  routeCoordinates
}) {
  const mapContainerRef = useRef(null);
  const mapRef = useRef(null);
  const markersRef = useRef([]);
  const baseMarkerRef = useRef(null);
  const disasterMarkerRef = useRef(null);
  const selectedMarkerRef = useRef(null);
  const routePolylineRef = useRef(null);
  const routeGlowRef = useRef(null);
  const tileLayerRef = useRef(null);
  const initialFitDoneRef = useRef(false);

  // Initialize Map
  useEffect(() => {
    if (typeof window === 'undefined') return;
    const L = require('leaflet');
    const targetLat = centerLat ?? lat;
    const targetLng = centerLng ?? lng;
    
    // Fix default marker icon issues in Webpack/Next.js
    delete L.Icon.Default.prototype._getIconUrl;
    L.Icon.Default.mergeOptions({
      iconRetinaUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png',
      iconUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png',
      shadowUrl: 'https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png',
    });

    if (!mapRef.current && mapContainerRef.current) {
      mapRef.current = L.map(mapContainerRef.current, {
        scrollWheelZoom: true,
        zoomControl: true,
        doubleClickZoom: true,
        touchZoom: true,
        boxZoom: true,
        dragging: true
      }).setView([targetLat, targetLng], 13);

      tileLayerRef.current = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; OpenStreetMap contributors'
      }).addTo(mapRef.current);

      if (fitBoundsLocations && disasterLocation && typeof disasterLocation.lat === 'number' && typeof disasterLocation.lng === 'number') {
        const bounds = L.latLngBounds([[lat, lng], [disasterLocation.lat, disasterLocation.lng]]);
        mapRef.current.fitBounds(bounds, { padding: [60, 60], maxZoom: 12 });
        initialFitDoneRef.current = true;
      }

      setTimeout(() => {
        mapRef.current?.invalidateSize();
      }, 150);
    } else if (mapRef.current) {
      // Avoid jarring jumps if user is interacting, unless view mode/center shifts significantly
      if (fitBoundsLocations && disasterLocation && !initialFitDoneRef.current) {
        const bounds = L.latLngBounds([[lat, lng], [disasterLocation.lat, disasterLocation.lng]]);
        mapRef.current.fitBounds(bounds, { padding: [60, 60], maxZoom: 12 });
        initialFitDoneRef.current = true;
      } else if (!fitBoundsLocations) {
        const currentCenter = mapRef.current.getCenter();
        if (Math.abs(currentCenter.lat - targetLat) > 0.05 || Math.abs(currentCenter.lng - targetLng) > 0.05) {
          mapRef.current.setView([targetLat, targetLng], 13);
        }
      }
    }

    const map = mapRef.current;
    if (!map) return;

    // 1. Sync Govt Official Head Office Marker (Mysuru Depot Pin)
    if (baseMarkerRef.current) {
      baseMarkerRef.current.remove();
    }
    const baseIcon = L.divIcon({
      className: 'base-station-marker',
      html: `<div style="display: flex; align-items: center; justify-content: center; width: 32px; height: 32px; background: #1d4ed8; border: 2px solid #ffffff; border-radius: 50%; box-shadow: 0 2px 10px rgba(29,78,216,0.75);"><i class="fas fa-landmark" style="color: #ffffff; font-size: 14px;"></i></div>`,
      iconSize: [32, 32],
      iconAnchor: [16, 16]
    });
    baseMarkerRef.current = L.marker([lat, lng], { icon: baseIcon })
      .addTo(map)
      .bindPopup(`<b>🏛️ Govt Official Head Office (${name})</b><br>Mysuru Command &amp; Resource Depot<br>Lat: ${lat.toFixed(6)}, Lng: ${lng.toFixed(6)}`);

    // 1b. Sync Current Disaster Epicenter Marker (Current GPS / Disaster Zone)
    if (disasterMarkerRef.current) {
      disasterMarkerRef.current.remove();
      disasterMarkerRef.current = null;
    }
    const dLat = disasterLocation && typeof disasterLocation.lat === 'number' ? disasterLocation.lat : targetLat;
    const dLng = disasterLocation && typeof disasterLocation.lng === 'number' ? disasterLocation.lng : targetLng;
    if (disasterLocation && typeof disasterLocation.lat === 'number' && typeof disasterLocation.lng === 'number') {
      const disasterIcon = L.divIcon({
        className: 'disaster-epicenter-marker',
        html: `<div style="display: flex; align-items: center; justify-content: center; width: 32px; height: 32px; background: radial-gradient(circle at 30% 30%, #ef4444, #991b1b); border: 2.5px solid #ffffff; border-radius: 50%; box-shadow: 0 0 14px rgba(239,68,68,0.95);"><i class="fas fa-house-tsunami" style="color: #ffffff; font-size: 13px;"></i></div>`,
        iconSize: [32, 32],
        iconAnchor: [16, 16]
      });
      disasterMarkerRef.current = L.marker([dLat, dLng], { icon: disasterIcon })
        .addTo(map)
        .bindPopup(`<b>🚨 Current Disaster Location</b><br>${disasterLocation.source || 'Active Impact Zone'}<br>Lat: ${dLat.toFixed(6)}, Lng: ${dLng.toFixed(6)}`);
    }

    // 2. Clear old request, volunteer, and shelter markers
    markersRef.current.forEach(m => m.remove());
    markersRef.current = [];

    // 3. Add Shelters around current disaster location (Green sphere markers with house icon)
    const mockShelters = [
      { lat: dLat + 0.004, lng: dLng - 0.005, name: 'Current Zone Emergency Shelter A', capacity: '120/150' },
      { lat: dLat - 0.005, lng: dLng + 0.006, name: 'Sector Relief Camp Shelter B', capacity: '85/100' }
    ];
    mockShelters.forEach(s => {
      const shelterIcon = L.divIcon({
        className: 'shelter-marker',
        html: `<div style="background: radial-gradient(circle at 30% 30%, #22c55e, #15803d); width: 24px; height: 24px; border-radius: 50%; border: 2px solid white; display: flex; align-items: center; justify-content: center; box-shadow: 0 0 10px rgba(34,197,94,0.8);"><i class="fas fa-home" style="color: white; font-size: 11px;"></i></div>`,
        iconSize: [24, 24]
      });
      const shelterMarker = L.marker([s.lat, s.lng], { icon: shelterIcon })
        .addTo(map)
        .bindPopup(`<b>🟢 Shelter: ${s.name}</b><br>Capacity: ${s.capacity}<br>Status: Operational`);
      markersRef.current.push(shelterMarker);
    });

    // 4. Add Active Request Markers (Disaster Zones - Red spheres with exclamation triangle)
    requests.forEach(req => {
      if (req.status !== 'resolved') {
        const customIcon = L.divIcon({
          className: 'custom-request-marker',
          html: `<div style="background: radial-gradient(circle at 30% 30%, #ef4444, #b91c1c); width: 24px; height: 24px; border-radius: 50%; border: 2px solid white; display: flex; align-items: center; justify-content: center; box-shadow: 0 0 10px rgba(239,68,68,0.8);"><i class="fas fa-exclamation-triangle" style="color: white; font-size: 10px;"></i></div>`,
          iconSize: [24, 24]
        });

        const reqMarker = L.marker([req.lat, req.lng], { icon: customIcon })
          .addTo(map)
          .bindPopup(`
            <b>🚨 Disaster Zone: ${req.requestId} (${req.resourceType})</b><br>
            Severity: ${req.severity} | Affected: ${req.individualsAffected}<br>
            Priority Score: ${req.priorityScore}<br>
            Status: ${req.status.toUpperCase()}
          `);
        markersRef.current.push(reqMarker);
      }
    });

    // 5. Add Volunteer Markers (Rescue Teams - Blue spheres with shield icon)
    volunteers.forEach(v => {
      const icon = L.divIcon({
        className: 'volunteer-marker',
        html: `<div style="background: radial-gradient(circle at 30% 30%, #3b82f6, #1d4ed8); width: 24px; height: 24px; border-radius: 50%; border: 2px solid white; display: flex; align-items: center; justify-content: center; box-shadow: 0 0 8px rgba(59,130,246,0.8);"><i class="fas fa-user-shield" style="color: white; font-size: 10px;"></i></div>`,
        iconSize: [24, 24]
      });

      const volMarker = L.marker([v.lat, v.lng], { icon })
        .addTo(map)
        .bindPopup(`<b>🔵 Rescue Team: ${v.name}</b><br>Role: ${v.role}<br>Status: ${v.status.toUpperCase()}`);
      markersRef.current.push(volMarker);
    });

    // 6. Setup map click handler to emit location
    const onMapClicked = (e) => {
      if (onMapClick) {
        onMapClick({ lat: e.latlng.lat, lng: e.latlng.lng });
      }
    };
    map.on('click', onMapClicked);

    return () => {
      map.off('click', onMapClicked);
    };
  }, [lat, lng, name, centerLat, centerLng, disasterLocation, fitBoundsLocations, requests, volunteers, onMapClick]);

  // Keep Leaflet size synced on container resize and clean up cleanly on unmount
  useEffect(() => {
    const container = mapContainerRef.current;
    let observer = null;
    if (typeof ResizeObserver !== 'undefined' && container) {
      observer = new ResizeObserver(() => {
        mapRef.current?.invalidateSize();
      });
      observer.observe(container);
    }

    return () => {
      if (observer) observer.disconnect();
      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
        tileLayerRef.current = null;
        baseMarkerRef.current = null;
        disasterMarkerRef.current = null;
        selectedMarkerRef.current = null;
        routePolylineRef.current = null;
        routeGlowRef.current = null;
        markersRef.current = [];
      }
    };
  }, []);

  // 7. Draw Selected Location Marker dynamically
  useEffect(() => {
    if (!mapRef.current) return;
    const map = mapRef.current;
    const L = require('leaflet');

    if (selectedMarkerRef.current) {
      selectedMarkerRef.current.remove();
      selectedMarkerRef.current = null;
    }

    if (selectedLocation) {
      selectedMarkerRef.current = L.marker([selectedLocation.lat, selectedLocation.lng])
        .addTo(map)
        .bindPopup(`<b>Emergency Target Point</b><br>Lat: ${selectedLocation.lat.toFixed(6)}<br>Lng: ${selectedLocation.lng.toFixed(6)}`)
        .openPopup();
    }
  }, [selectedLocation]);

  // 8. Draw route polyline dynamically
  useEffect(() => {
    if (!mapRef.current) return;
    const map = mapRef.current;
    const L = require('leaflet');

    if (routePolylineRef.current) {
      routePolylineRef.current.remove();
      routePolylineRef.current = null;
    }
    if (routeGlowRef.current) {
      routeGlowRef.current.remove();
      routeGlowRef.current = null;
    }

    if (routeCoordinates && routeCoordinates.length > 0) {
      // Standard vibrant blue route line
      routePolylineRef.current = L.polyline(routeCoordinates, {
        color: '#2563eb',
        weight: 5,
        opacity: 0.85
      }).addTo(map);
      map.fitBounds(routePolylineRef.current.getBounds(), { padding: [50, 50] });
    }
  }, [routeCoordinates]);

  return (
    <div style={{ display: 'flex', flexDirection: 'row', height: '100%', width: '100%', borderRadius: '12px', overflow: 'hidden' }}>
      {/* Map Container (90% split) */}
      <div style={{ width: '90%', position: 'relative', minHeight: '400px', height: '100%' }}>
        <div ref={mapContainerRef} style={{ height: '100%', width: '100%' }} />
      </div>
      
      {/* Scroll Safe Zone (10% split - completely empty) */}
      <div style={{ width: '10%', background: 'transparent' }} />
    </div>
  );
}

