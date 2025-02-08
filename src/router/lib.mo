import Types "../types";
import Text "mo:base/Text";
import Array "mo:base/Array";
import Pipeline "../pipeline";
import Parser "../parser";
import TextX "mo:xtended-text/TextX";

module Module {

    public class RouteContext(route_ : Route, params_ : [(Text, RouteParameterValue)]) = self {
        public let route : Route = route_;
        public let params : [(Text, RouteParameterValue)] = params_;

        public func getParam(key : Text) : ?RouteParameterValue {
            let ?kv = Array.find(
                params,
                func(kv : (Text, RouteParameterValue)) : Bool = TextX.equalIgnoreCase(kv.0, key),
            ) else return null;
            ?kv.1;
        };

        public func run(httpContext : Parser.HttpContext) : Types.HttpResponse {
            route.handler(httpContext, self);
        };
    };

    public type RouteHandler = (Parser.HttpContext, RouteContext) -> Types.HttpResponse;

    public type RouteParameterValue = {
        #text : Text;
        #int : Int;
    };

    public type RouteParameterType = {
        #text;
        #int;
    };

    public type Route = {
        path : Text;
        params : [(Text, RouteParameterType)];
        // TODO methods
        handler : RouteHandler;
    };

    public type RouterData = {
        routes : [Route];
    };

    public func empty() : RouterData {
        {
            routes = [];
        };
    };

    public func route(data : RouterData, path : Text, handler : RouteHandler) : RouterData {
        let route = {
            path = path;
            params = [];
            handler = handler;
        };

        {
            routes = Array.append(data.routes, [route]);
        };
    };

    public func build(data : RouterData) : Router {
        Router(data);
    };

    public func use(pipeline : Pipeline.PipelineData, router : Router) : Pipeline.PipelineData {
        let middleware = {
            handle = func(httpContext : Parser.HttpContext, next : Pipeline.Next) : Types.HttpResponse {
                let ?response = router.route(httpContext) else return next();
                response;
            };
        };

        {
            middleware = Array.append(pipeline.middleware, [middleware]);
        };
    };

    public class Router(routerData : RouterData) = self {
        let routes = routerData.routes;

        public func route(httpContext : Parser.HttpContext) : ?Types.HttpResponse {
            let ?routeContext = findRoute(httpContext) else return null;

            ?routeContext.run(httpContext);
        };

        private func findRoute(httpContext : Parser.HttpContext) : ?RouteContext {
            // TODO this is placeholder

            let path = httpContext.getPath();
            let ?route = routes
            |> Array.find(
                _,
                func(route : Route) : Bool = TextX.equalIgnoreCase(route.path, path),
            ) else return null;

            ?RouteContext(route, []);
        };

    };
};
