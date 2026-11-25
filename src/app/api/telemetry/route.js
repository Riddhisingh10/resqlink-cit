import fs from 'fs';
import path from 'path';

const dataFilePath = path.join(process.cwd(), 'src/data/telemetry.json');

const DEFAULT_TELEMETRY = {
  temperature: 24.5,
  humidity: 62.0,
  soil_moisture: 2100,
  water_level: 120.0,
  seismic: 0.05,
  air_quality: 180,
  rain_level: 0,
  baro_pressure: 1011.5,
  altitude: 770.0,
  wind_speed: 12.5,
  wind_direction: 190,
  latitude: 12.5118,
  longitude: 76.8851,
  lora_node: "LORA-NODE-01",
  lora_rssi: -68,
  status: "Online Active",
  created_at: new Date().toISOString()
};

function readTelemetry() {
  try {
    if (!fs.existsSync(dataFilePath)) {
      fs.mkdirSync(path.dirname(dataFilePath), { recursive: true });
      fs.writeFileSync(dataFilePath, JSON.stringify(DEFAULT_TELEMETRY, null, 2));
      return DEFAULT_TELEMETRY;
    }
    const raw = fs.readFileSync(dataFilePath, 'utf8');
    return JSON.parse(raw);
  } catch (err) {
    console.error('Error reading telemetry file:', err);
    return DEFAULT_TELEMETRY;
  }
}

function writeTelemetry(data) {
  try {
    fs.mkdirSync(path.dirname(dataFilePath), { recursive: true });
    fs.writeFileSync(dataFilePath, JSON.stringify(data, null, 2), 'utf8');
    return true;
  } catch (err) {
    console.error('Error saving telemetry file:', err);
    return false;
  }
}

// GET: Returns current real-time hardware telemetry
export async function GET() {
  const telemetry = readTelemetry();
  return Response.json(telemetry);
}

// POST: Accepts hardware telemetry directly from ESP32 or demo triggers
export async function POST(request) {
  try {
    const body = await request.json();
    const current = readTelemetry();

    const updated = {
      ...current,
      ...body,
      created_at: new Date().toISOString(),
      status: body.status || "Live Hardware Sync"
    };

    writeTelemetry(updated);

    return Response.json({
      success: true,
      message: "Telemetry updated successfully",
      telemetry: updated
    });
  } catch (err) {
    console.error('POST telemetry error:', err);
    return Response.json({ error: 'Invalid telemetry structure' }, { status: 400 });
  }
}
