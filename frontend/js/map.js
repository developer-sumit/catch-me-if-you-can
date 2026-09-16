// Google Maps Integration

let map = null;
let markers = [];
let directionsService = null;
let directionsRenderer = null;
let googleMapsLoaded = false;

const darkMapStyles = [
  { elementType: 'geometry', stylers: [{ color: '#242f3e' }] },
  { elementType: 'labels.text.stroke', stylers: [{ color: '#242f3e' }] },
  { elementType: 'labels.text.fill', stylers: [{ color: '#746855' }] },
  { featureType: 'administrative.locality', elementType: 'labels.text.fill', stylers: [{ color: '#d59563' }] },
  { featureType: 'poi', elementType: 'labels.text.fill', stylers: [{ color: '#d59563' }] },
  { featureType: 'poi.park', elementType: 'geometry', stylers: [{ color: '#263c3f' }] },
  { featureType: 'poi.park', elementType: 'labels.text.fill', stylers: [{ color: '#6b9a76' }] },
  { featureType: 'road', elementType: 'geometry', stylers: [{ color: '#38414e' }] },
  { featureType: 'road', elementType: 'geometry.stroke', stylers: [{ color: '#212a37' }] },
  { featureType: 'road', elementType: 'labels.text.fill', stylers: [{ color: '#9ca5b3' }] },
  { featureType: 'road.highway', elementType: 'geometry', stylers: [{ color: '#746855' }] },
  { featureType: 'road.highway', elementType: 'geometry.stroke', stylers: [{ color: '#1f2835' }] },
  { featureType: 'road.highway', elementType: 'labels.text.fill', stylers: [{ color: '#f3d19c' }] },
  { featureType: 'transit', elementType: 'geometry', stylers: [{ color: '#2f3948' }] },
  { featureType: 'transit.station', elementType: 'labels.text.fill', stylers: [{ color: '#d59563' }] },
  { featureType: 'water', elementType: 'geometry', stylers: [{ color: '#17263c' }] },
  { featureType: 'water', elementType: 'labels.text.fill', stylers: [{ color: '#515c6d' }] },
  { featureType: 'water', elementType: 'labels.text.stroke', stylers: [{ color: '#17263c' }] }
];

async function loadGoogleMaps() {
  if (googleMapsLoaded) return;
  if (document.getElementById('google-maps-script')) {
    return new Promise(resolve => {
      const interval = setInterval(() => {
        if (googleMapsLoaded) { clearInterval(interval); resolve(); }
      }, 100);
    });
  }

  try {
    const res = await api.get('/config');
    const apiKey = res.googleMapsApiKey;
    
    if (!apiKey) {
      console.error('Google Maps API key is missing. Add it to .env');
      return;
    }

    return new Promise((resolve, reject) => {
      window.initGoogleMapsCallback = () => {
        googleMapsLoaded = true;
        resolve();
      };
      const script = document.createElement('script');
      script.id = 'google-maps-script';
      script.src = `https://maps.googleapis.com/maps/api/js?key=${apiKey}&callback=initGoogleMapsCallback`;
      script.async = true;
      script.defer = true;
      script.onerror = reject;
      document.head.appendChild(script);
    });
  } catch (err) {
    console.error('Failed to load Google Maps configuration:', err);
  }
}

async function initMap(containerId, centerLat = 28.6139, centerLng = 77.2090, zoom = 12) {
  await loadGoogleMaps();
  if (!googleMapsLoaded) return null;

  const mapOptions = {
    zoom: zoom,
    center: { lat: centerLat, lng: centerLng },
    mapTypeId: 'roadmap',
    styles: darkMapStyles,
    disableDefaultUI: false
  };

  map = new google.maps.Map(document.getElementById(containerId), mapOptions);
  directionsService = new google.maps.DirectionsService();
  directionsRenderer = new google.maps.DirectionsRenderer({
    map: map,
    suppressMarkers: true,
    polylineOptions: { strokeColor: '#10b981', strokeWeight: 5, strokeOpacity: 0.8 }
  });

  return map;
}

async function initPickerMap(containerId, onClickCallback) {
  await loadGoogleMaps();
  if (!googleMapsLoaded) return null;
  
  const pMap = new google.maps.Map(document.getElementById(containerId), {
    zoom: 11,
    center: { lat: 28.6139, lng: 77.2090 },
    styles: darkMapStyles,
    disableDefaultUI: true,
    zoomControl: true
  });
  
  let currentMarker = null;
  
  pMap.addListener('click', (e) => {
    const lat = e.latLng.lat();
    const lng = e.latLng.lng();
    if (currentMarker) currentMarker.setMap(null);
    currentMarker = new google.maps.Marker({
      position: { lat, lng },
      map: pMap,
      animation: google.maps.Animation.DROP
    });
    if (onClickCallback) onClickCallback(lat, lng);
  });
  
  return pMap;
}

function clearMarkers() {
  markers.forEach(m => m.setMap(null));
  markers = [];
}

function createMarkerIcon(emoji, bgColor) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36"><circle cx="18" cy="18" r="16" fill="${bgColor}" stroke="#ffffff" stroke-width="2"/><text x="18" y="25" font-size="18" text-anchor="middle" fill="#ffffff">${emoji}</text></svg>`;
  return {
    url: 'data:image/svg+xml;charset=UTF-8,' + encodeURIComponent(svg),
    scaledSize: new google.maps.Size(36, 36),
    anchor: new google.maps.Point(18, 18)
  };
}

function addKitchenMarker(lat, lng, popupHtml, onClick) {
  if (!googleMapsLoaded) return;
  const marker = new google.maps.Marker({
    position: { lat, lng },
    map: map,
    icon: createMarkerIcon('🍳', '#10b981')
  });

  if (popupHtml) {
    const infoWindow = new google.maps.InfoWindow({ content: popupHtml });
    marker.addListener('click', () => {
      infoWindow.open(map, marker);
      if (onClick) onClick();
    });
  } else if (onClick) {
    marker.addListener('click', onClick);
  }
  markers.push(marker);
  return marker;
}

function addNGOMarker(lat, lng, popupHtml) {
  if (!googleMapsLoaded) return;
  const marker = new google.maps.Marker({
    position: { lat, lng },
    map: map,
    icon: createMarkerIcon('🏢', '#3b82f6')
  });

  if (popupHtml) {
    const infoWindow = new google.maps.InfoWindow({ content: popupHtml });
    marker.addListener('click', () => infoWindow.open(map, marker));
  }
  markers.push(marker);
  return marker;
}

function showRoute(waypoints) {
  if (!directionsService || !directionsRenderer || !waypoints || waypoints.length < 2) return;

  const origin = waypoints[0];
  const destination = waypoints[waypoints.length - 1];
  const stops = waypoints.slice(1, waypoints.length - 1).map(p => ({
    location: { lat: p.lat, lng: p.lng },
    stopover: true
  }));

  const request = {
    origin: { lat: origin.lat, lng: origin.lng },
    destination: { lat: destination.lat, lng: destination.lng },
    waypoints: stops,
    optimizeWaypoints: true,
    travelMode: 'DRIVING'
  };

  directionsService.route(request, (result, status) => {
    if (status == 'OK') {
      directionsRenderer.setDirections(result);
    } else {
      console.error('Directions request failed due to ' + status);
    }
  });
}

function fitMapToMarkers() {
  if (markers.length > 0 && map) {
    const bounds = new google.maps.LatLngBounds();
    markers.forEach(m => bounds.extend(m.getPosition()));
    map.fitBounds(bounds);
    
    if (markers.length === 1) {
      map.setZoom(14);
    }
  }
}
