import { MapContainer, TileLayer, CircleMarker, Popup } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import type { Report } from '../types';
import { departmentLabels, priorityColor, statusLabels, typeLabels } from '../labels';

const MUSCAT: [number, number] = [23.5859, 58.4059];

interface Props {
  reports: Report[];
  selectedId: string | null;
  onSelect: (id: string) => void;
}

export default function MapView({ reports, selectedId, onSelect }: Props) {
  const withLocation = reports.filter((r) => r.latitude != null && r.longitude != null);
  const center: [number, number] = withLocation.length
    ? [withLocation[0].latitude as number, withLocation[0].longitude as number]
    : MUSCAT;

  return (
    <MapContainer center={center} zoom={12} style={{ height: '100%', width: '100%' }}>
      <TileLayer attribution="&copy; OpenStreetMap contributors" url="https://tile.openstreetmap.org/{z}/{x}/{y}.png" />
      {withLocation.map((r) => (
        <CircleMarker
          key={r.report_id}
          center={[r.latitude as number, r.longitude as number]}
          radius={r.report_id === selectedId ? 13 : 9}
          pathOptions={{
            color: '#ffffff',
            weight: r.report_id === selectedId ? 3 : 1.5,
            fillColor: priorityColor(r.priority),
            fillOpacity: 0.9,
          }}
          eventHandlers={{ click: () => onSelect(r.report_id) }}
        >
          <Popup>
            <div style={{ direction: 'rtl', textAlign: 'right', fontFamily: 'Tajawal, sans-serif' }}>
              <strong>{typeLabels[r.confirmed_incident_type] ?? r.confirmed_incident_type}</strong>
              <div>{departmentLabels[r.department] ?? r.department}</div>
              <div>{statusLabels[r.status] ?? r.status}</div>
              <div style={{ color: '#5B6478', fontSize: 12 }}>{r.location_text}</div>
            </div>
          </Popup>
        </CircleMarker>
      ))}
    </MapContainer>
  );
}
