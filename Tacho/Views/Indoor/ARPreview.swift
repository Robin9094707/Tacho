import SwiftUI
import ARKit
import SceneKit
import Metal

/// Live-Kamerabild mit Merkmalspunkten, erkannten Flächen und LiDAR-Raumgitter.
struct ARPreview: UIViewRepresentable {
    let session: ARSession
    var showMesh: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = true
        view.rendersCameraGrain = false
        view.debugOptions = [.showFeaturePoints]
        view.delegate = context.coordinator
        context.coordinator.showMesh = showMesh
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        context.coordinator.showMesh = showMesh
        view.scene.rootNode.enumerateChildNodes { node, _ in
            if node.name == "mesh" { node.isHidden = !showMesh }
        }
    }

    final class Coordinator: NSObject, ARSCNViewDelegate {
        var showMesh = true

        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            if let mesh = anchor as? ARMeshAnchor {
                let node = SCNNode(geometry: Self.geometry(from: mesh.geometry))
                node.name = "mesh"
                node.isHidden = !showMesh
                return node
            }
            if let plane = anchor as? ARPlaneAnchor,
               let device = renderer.device,
               let geo = ARSCNPlaneGeometry(device: device) {
                geo.update(from: plane.geometry)
                let m = SCNMaterial()
                m.diffuse.contents = Self.color(for: plane).withAlphaComponent(0.28)
                m.lightingModel = .constant
                m.isDoubleSided = true
                geo.materials = [m]
                let node = SCNNode(geometry: geo)
                node.name = "plane"
                return node
            }
            return nil
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            if let mesh = anchor as? ARMeshAnchor {
                node.geometry = Self.geometry(from: mesh.geometry)
                node.isHidden = !showMesh
            } else if let plane = anchor as? ARPlaneAnchor, let geo = node.geometry as? ARSCNPlaneGeometry {
                geo.update(from: plane.geometry)
                geo.firstMaterial?.diffuse.contents = Self.color(for: plane).withAlphaComponent(0.28)
            }
        }

        static func color(for plane: ARPlaneAnchor) -> UIColor {
            switch plane.classification {
            case .wall: return .systemBlue
            case .floor: return .systemGreen
            case .ceiling: return .systemPurple
            case .door: return .systemOrange
            case .window: return .systemTeal
            case .table: return .systemYellow
            case .seat: return .systemPink
            default: return .white
            }
        }

        static func geometry(from g: ARMeshGeometry) -> SCNGeometry {
            let v = g.vertices
            let source = SCNGeometrySource(buffer: v.buffer,
                                           vertexFormat: v.format,
                                           semantic: .vertex,
                                           vertexCount: v.count,
                                           dataOffset: v.offset,
                                           dataStride: v.stride)
            let f = g.faces
            let length = f.count * f.indexCountPerPrimitive * f.bytesPerIndex
            let data = Data(bytes: f.buffer.contents(), count: length)
            let element = SCNGeometryElement(data: data,
                                             primitiveType: .triangles,
                                             primitiveCount: f.count,
                                             bytesPerIndex: f.bytesPerIndex)
            let geo = SCNGeometry(sources: [source], elements: [element])
            let m = SCNMaterial()
            m.fillMode = .lines
            m.diffuse.contents = UIColor.cyan.withAlphaComponent(0.75)
            m.lightingModel = .constant
            m.isDoubleSided = true
            geo.materials = [m]
            return geo
        }
    }
}
