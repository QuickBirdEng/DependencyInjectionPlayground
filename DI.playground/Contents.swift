import UIKit
import XCTest

class Repository<Type> {
    func getAll() -> [Type] {
        fatalError()
    }
}

class DatabaseRepository<Type>: Repository<Type> {}

struct Article: Equatable {
    let title: String
}

class Basket {
    var articles = [Article]()
}

class BasketService {
    private let repository: Repository<Article>

    init(repository: Repository<Article> = DatabaseRepository()) {
        self.repository = repository
    }

    func addAllArticles(to basket: Basket) {
        let allArticles = repository.getAll()
        basket.articles.append(contentsOf: allArticles)
    }
}

class MockRepository<Type>: Repository<Type> {

    var objects: [Type]

    init(objects: [Type]) {
        self.objects = objects
    }

    override func getAll() -> [Type] {
        return objects
    }
}

class BasketServiceTests: XCTestCase {
    func testAddAllArticles() {
        let expectedArticle = Article(title: "Article 1")
        let mockRepository = MockRepository<Article>(objects: [expectedArticle])
        let basketService = BasketService(repository: mockRepository)
        let basket = Basket()

        basketService.addAllArticles(to: basket)

        XCTAssertEqual(basket.articles.count, 1)
        XCTAssertEqual(basket.articles[0], expectedArticle)
    }
}

BasketServiceTests.defaultTestSuite.run()

class BasketViewController: UIViewController {
    var basketService: BasketService = BasketService()
}

//let basketViewController = BasketViewController()
//basketViewController.basketService = BasketService()

protocol BasketFactory {
    func makeBasketService() -> BasketService
    func makeBasketViewController() -> BasketViewController
}

class DefaultBasketFactory: BasketFactory {

    func makeBasketService() -> BasketService {
        let repository = makeArticleRepository()
        return BasketService(repository: repository)
    }

    func makeBasketViewController() -> BasketViewController {
        let basketViewController = BasketViewController()
        basketViewController.basketService = makeBasketService()
        return basketViewController
    }

    // MARK: Private factory methods

    private func makeArticleRepository() -> Repository<Article> {
        return DatabaseRepository()
    }

}

let factory = DefaultBasketFactory()

let basketViewController2 = factory.makeBasketViewController()

protocol Resolver {
    func resolve<ServiceType>(_ type: ServiceType.Type) -> ServiceType
}

struct Container: Resolver {

    let factories: [AnyServiceFactory]

    init() {
        self.factories = []
    }

    private init(factories: [AnyServiceFactory]) {
        self.factories = factories
    }

    // MARK: Register

    func register<T>(_ interface: T.Type, instance: T) -> Container {
        return register(interface) { _ in instance }
    }

    func register<ServiceType>(_ type: ServiceType.Type, _ factory: @escaping (Resolver) -> ServiceType) -> Container {
        assert(!factories.contains(where: { $0.supports(type) }))

        let newFactory = BasicServiceFactory<ServiceType>(type, factory: { resolver in
            factory(resolver)
        })
        return .init(factories: factories + [AnyServiceFactory(newFactory)])
    }

    // MARK: Resolver

    func resolve<ServiceType>(_ type: ServiceType.Type) -> ServiceType {
        guard let factory = factories.first(where: { $0.supports(type) }) else {
            fatalError("No suitable factory found")
        }
        return factory.resolve(self)
    }

    func factory<ServiceType>(for type: ServiceType.Type) -> () -> ServiceType {
        guard let factory = factories.first(where: { $0.supports(type) }) else {
            fatalError("No suitable factory found")
        }

        return { factory.resolve(self) }
    }
}

protocol ServiceFactory {
    associatedtype ServiceType

    func resolve(_ resolver: Resolver) -> ServiceType
}

extension ServiceFactory {
    func supports<T>(_ type: T.Type) -> Bool {
        return type == ServiceType.self
    }
}

extension Resolver {
    func factory<ServiceType>(for type: ServiceType.Type) -> () -> ServiceType {
        return { self.resolve(type) }
    }
}

struct BasicServiceFactory<ServiceType>: ServiceFactory {
    private let factory: (Resolver) -> ServiceType

    init(_ type: ServiceType.Type, factory: @escaping (Resolver) -> ServiceType) {
        self.factory = factory
    }

    func resolve(_ resolver: Resolver) -> ServiceType {
        return factory(resolver)
    }
}

final class AnyServiceFactory {
    private let _resolve: (Resolver) -> Any
    private let _supports: (Any.Type) -> Bool

    init<T: ServiceFactory>(_ serviceFactory: T) {
        self._resolve = { resolver -> Any in
            serviceFactory.resolve(resolver)
        }
        self._supports = { $0 == T.ServiceType.self }
    }

    func resolve<ServiceType>(_ resolver: Resolver) -> ServiceType {
        return _resolve(resolver) as! ServiceType
    }

    func supports<ServiceType>(_ type: ServiceType.Type) -> Bool {
        return _supports(type)
    }
}

let basketContainer = Container()
    .register(Bundle.self, instance: Bundle.main)
    .register(Repository<Article>.self) { _ in DatabaseRepository() }
    .register(BasketService.self) { resolver in
        let repository = resolver.resolve(Repository<Article>.self)
        return BasketService(repository: repository)
    }
    .register(BasketViewController.self) { resolver in
        let basketViewController = BasketViewController()
        basketViewController.basketService = resolver.resolve(BasketService.self)
        return basketViewController
    }

let basketViewController = basketContainer.resolve(BasketViewController.self)

let basketVCFactory = basketContainer.factory(for: BasketViewController.self)
let basketViewController3 = basketVCFactory()

class HomeViewController: UIViewController {
    var basketViewControllerFactory: () -> BasketViewController = { fatalError("Factory must be injected") }

    func showBasketView() {
        let basketViewController = basketViewControllerFactory()
        self.present(basketViewController, animated: true, completion: nil)
    }
}

let mainContainer = basketContainer
    .register(HomeViewController.self) { resolver in
        let homeViewController = HomeViewController()
        homeViewController.basketViewControllerFactory = resolver.factory(for: BasketViewController.self)
        return homeViewController
    }

let homeVC = mainContainer.resolve(HomeViewController.self)
homeVC.showBasketView()
